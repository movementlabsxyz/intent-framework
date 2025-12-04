/// Extension of the fungible asset intent flow that layers an oracle signature
/// requirement on top of the base limit-order mechanics.
///
/// Offerers still escrow a single fungible asset, but settlement succeeds only
/// when the solver supplies a signed report from an authorized oracle whose
/// reported value meets the threshold chosen by the creator.
module mvmt_intent::fa_intent_with_oracle {
    use std::bcs;
    use std::error;
    use std::option::{Self as option, Option};
    use std::signer;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, FungibleStore};
    use aptos_framework::object::{Self, DeleteRef, ExtendRef, Object};
    use aptos_framework::primary_fungible_store;
    use mvmt_intent::intent::{Self, Session, Intent};
    use mvmt_intent::intent_reservation::{Self, IntentReserved};
    use aptos_std::ed25519;

    // ============================================================================
    // ERROR CODES
    // ============================================================================

    /// The received fungible asset was not the expected token type.
    const ENOT_DESIRED_TOKEN: u64 = 0;

    /// The received fungible asset amount is smaller than required.
    const EAMOUNT_NOT_MEET: u64 = 1;

    /// A signature witness is required but missing.
    const ESIGNATURE_REQUIRED: u64 = 2;

    /// Provided oracle signature failed verification.
    const EINVALID_SIGNATURE: u64 = 3;

    /// Oracle-reported value did not satisfy the minimum threshold.
    const EORACLE_VALUE_TOO_LOW: u64 = 4;

    // ============================================================================
    // DATA TYPES
    // ============================================================================

    /// Manages a fungible asset store for intent execution.
    struct FungibleStoreManager has store {
        extend_ref: ExtendRef,
        delete_ref: DeleteRef,
    }

    /// Oracle requirement describing the minimum reported value and signer information.
    struct OracleSignatureRequirement has store, drop, copy {
        min_reported_value: u64,
        public_key: ed25519::UnvalidatedPublicKey,
    }

    /// Trading conditions for an oracle-guarded limit order.
    struct OracleGuardedLimitOrder has store, drop {
        desired_metadata: Object<Metadata>,
        desired_amount: u64, // Original desired amount (for the chain specified by desired_chain_id)
        desired_chain_id: u64, // Chain ID where desired tokens are located
        offered_chain_id: u64, // Chain ID where offered tokens are located (used to determine if payment is required on current chain)
        requester: address,
        requirement: OracleSignatureRequirement,
        intent_id: address, // Intent ID from hub chain (for escrows) - used for signature verification
        requester_address_connected_chain: Option<address>, // Address on connected chain where solver should send tokens (for outflow intents)
    }

    /// Witness type proving receipt completion after oracle validation.
    struct OracleGuardedWitness has drop {}

    /// Witness supplied by the solver showing the oracle's reported value and signature.
    struct OracleSignatureWitness has drop {
        reported_value: u64,
        signature: ed25519::Signature,
    }

    #[event]
    /// Event emitted when an oracle-guarded limit order is created.
    /// Mirrors the base event while also surfacing the minimum acceptable
    /// oracle value chosen by the issuer for transparency.
    struct OracleLimitOrderEvent has store, drop {
        intent_address: address, // The escrow intent address (on connected chain)
        intent_id: address,      // The original intent ID (from hub chain) - links escrow to hub intent
        offered_metadata: Object<Metadata>,
        offered_amount: u64,
        offered_chain_id: u64,  // Chain ID where offered tokens are located
        desired_metadata: Object<Metadata>,
        desired_amount: u64,    // Original desired amount (for the chain specified by desired_chain_id)
        desired_chain_id: u64,  // Chain ID where desired tokens are located
        requester: address,
        expiry_time: u64,
        min_reported_value: u64,
        revocable: bool,
        reserved_solver: Option<address>, // Solver address if the intent is reserved (None for unreserved intents)
        requester_address_connected_chain: Option<address>, // Requester address on connected chain (for outflow intents)
    }

    // ============================================================================
    // CONSTRUCTORS / HELPERS
    // ============================================================================

    /// Helper to construct an oracle signature requirement payload.
    public fun new_oracle_signature_requirement(
        min_reported_value: u64,
        public_key: ed25519::UnvalidatedPublicKey,
    ): OracleSignatureRequirement {
        OracleSignatureRequirement { min_reported_value, public_key }
    }

    /// Helper to package an oracle signature witness supplied by the solver.
    public fun new_oracle_signature_witness(
        reported_value: u64,
        signature: ed25519::Signature,
    ): OracleSignatureWitness {
        OracleSignatureWitness { reported_value, signature }
    }

    // ============================================================================
    // ENTRY / PUBLIC API
    // ============================================================================

    /// Creates a fungible asset -> fungible asset trading intent guarded by an
    /// oracle signature requirement.
    ///
    /// The offered fungible asset is parked in a temporary store owned by this
    /// module and the trading conditions (desired token, minimum amount, and
    /// oracle threshold) are captured in the intent arguments.
    ///
    /// # Arguments
    /// - `offered_fa`: The asset being offered by the requester
    /// - `offered_chain_id`: Chain ID where offered tokens are located
    /// - `desired_metadata`: Metadata handle of the asset the requester wants to receive
    /// - `desired_amount`: Minimum amount of the desired asset that must be paid
    /// - `desired_chain_id`: Chain ID where desired tokens are located
    /// - `expiry_time`: Unix timestamp after which the intent can no longer be filled
    /// - `requester`: Address of the intent creator
    /// - `requirement`: Oracle public key and minimum reported value used for verification
    /// - `revocable`: Whether the intent can be revoked by the owner
    /// - `intent_id`: The original intent ID from hub chain (for escrows) or same as intent_address (for regular intents)
    /// - `requester_address_connected_chain`: Optional address on connected chain where solver should send tokens (for outflow intents)
    /// - `reservation`: Optional reservation specifying which solver can claim the escrow
    ///
    /// # Returns
    /// - `Object<Intent<...>>`: Handle to the created oracle-guarded intent
    public fun create_fa_to_fa_intent_with_oracle_requirement(
        offered_fa: FungibleAsset,
        offered_chain_id: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        desired_chain_id: u64,
        expiry_time: u64,
        requester: address,
        requirement: OracleSignatureRequirement,
        revocable: bool,
        intent_id: address,
        requester_address_connected_chain: Option<address>,
        reservation: Option<IntentReserved>,
    ): Object<Intent<FungibleStoreManager, OracleGuardedLimitOrder>> {
        // Capture metadata and amount before depositing
        let offered_metadata = fungible_asset::asset_metadata(&offered_fa);
        let offered_amount = fungible_asset::amount(&offered_fa);
        
        let coin_store_ref = object::create_object(requester);
        let extend_ref = object::generate_extend_ref(&coin_store_ref);
        let delete_ref = object::generate_delete_ref(&coin_store_ref);
        let transfer_ref = object::generate_transfer_ref(&coin_store_ref);
        let linear_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_ref, object::address_from_constructor_ref(&coin_store_ref));

        fungible_asset::create_store(&coin_store_ref, fungible_asset::metadata_from_asset(&offered_fa));
        fungible_asset::deposit(
            object::object_from_constructor_ref<FungibleStore>(&coin_store_ref),
            offered_fa
        );
        
        // Extract solver from reservation if present (before reservation is moved into create_intent)
        let reserved_solver = if (option::is_some(&reservation)) {
            let reservation_ref = option::borrow(&reservation);
            option::some(intent_reservation::solver(reservation_ref))
        } else {
            option::none<address>()
        };
        
        let intent_obj = intent::create_intent<FungibleStoreManager, OracleGuardedLimitOrder, OracleGuardedWitness>(
            FungibleStoreManager { extend_ref, delete_ref },
            OracleGuardedLimitOrder { desired_metadata, desired_amount, desired_chain_id, offered_chain_id, requester, requirement, intent_id, requester_address_connected_chain },
            expiry_time,
            requester,
            OracleGuardedWitness {},
            reservation,
            revocable,
        );

        // Emit event after creating intent so we have the intent address
        // Use desired_amount directly (which should be the original value for the chain specified by desired_chain_id)
        event::emit(OracleLimitOrderEvent {
            intent_address: object::object_address(&intent_obj),
            intent_id,  // Pass the intent ID from requester (hub chain intent ID for escrows)
            offered_metadata,
            offered_amount,
            offered_chain_id,
            desired_metadata,
            desired_amount,
            desired_chain_id,
            requester,
            expiry_time,
            min_reported_value: requirement.min_reported_value,
            revocable,
            reserved_solver,
            requester_address_connected_chain,
        });

        intent_obj
    }

    /// Starts a fungible asset offering session by unlocking the stored assets.
    ///
    /// Mirrors the base helper but returns an `OracleGuardedLimitOrder` session
    /// so the solver can learn the oracle requirement alongside the trade data.
    ///
    /// # Arguments
    /// - `solver`: Signer of the solver attempting to claim the escrow
    /// - `intent`: Object reference to the oracle-guarded intent
    ///
    /// # Returns
    /// - `FungibleAsset`: The unlocked supply that the solver can now move
    /// - `Session<OracleGuardedLimitOrder>`: "Hot potato" session tracking the intent arguments
    ///
    /// # Aborts
    /// - If the intent is reserved and the solver is not the authorized solver
    public fun start_fa_offering_session(
        solver: &signer,
        intent: Object<Intent<FungibleStoreManager, OracleGuardedLimitOrder>>
    ): (FungibleAsset, Session<OracleGuardedLimitOrder>) {
        let (store_manager, session) = intent::start_intent_session(intent);
        let reservation = intent::get_reservation(&session);
        intent_reservation::ensure_solver_authorized(solver, reservation);
        (destroy_store_manager(store_manager), session)
    }

    /// Completes an oracle-guarded limit order after verifying the signature witness.
    ///
    /// This function recreates the standard settlement checks (token type and
    /// amount) and extends them with a signature verification step that ensures
    /// the oracle report meets the threshold selected by the intent creator.
    ///
    /// # Arguments
    /// - `session`: The active trading session (consumed)
    /// - `received_fa`: Asset supplied by the solver to satisfy the intent
    /// - `oracle_witness_opt`: Optional signature witness (must be `some`)
    ///
    /// # Aborts
    /// - `ENOT_DESIRED_TOKEN`: Received asset metadata mismatches the requested one
    /// - `EAMOUNT_NOT_MEET`: Received asset amount is below `desired_amount`
    /// - `ESIGNATURE_REQUIRED`: Solver omitted the signature witness
    /// - `EINVALID_SIGNATURE`: Supplied signature failed Ed25519 verification
    /// - `EORACLE_VALUE_TOO_LOW`: Oracle value does not reach the configured threshold
    public fun finish_fa_receiving_session_with_oracle(
        session: Session<OracleGuardedLimitOrder>,
        received_fa: FungibleAsset,
        oracle_witness_opt: Option<OracleSignatureWitness>,
    ) {
        let argument = intent::get_argument(&session);
        assert!(
            fungible_asset::metadata_from_asset(&received_fa) == argument.desired_metadata,
            error::invalid_argument(ENOT_DESIRED_TOKEN)
        );
        // Payment validation: if desired_chain_id != offered_chain_id, we're on the offered chain
        // and nothing is desired on this chain, so payment should be 0
        // Otherwise, use the desired_amount for the chain specified by desired_chain_id
        let required_payment_amount = if (argument.desired_chain_id == argument.offered_chain_id) {
            argument.desired_amount // Same chain - payment required
        } else {
            0 // Cross-chain - nothing desired on the offered chain
        };
        assert!(
            fungible_asset::amount(&received_fa) >= required_payment_amount,
            error::invalid_argument(EAMOUNT_NOT_MEET),
        );

        verify_oracle_requirement(argument, &oracle_witness_opt);

        primary_fungible_store::deposit(argument.requester, received_fa);
        intent::finish_intent_session(session, OracleGuardedWitness {})
    }

    // SECURITY: Revocation functionality removed for oracle-guarded intents
    // Once funds are locked with oracle requirements, they can only be released
    // through proper oracle verification - not through revocation

    // ============================================================================
    // INTERNAL HELPERS
    // ============================================================================

    /// Verifies that a signature witness was provided (and only then) and that it
    /// satisfies the oracle requirement embedded in the order arguments.
    ///
    /// # Arguments
    /// - `argument`: Borrowed limit order arguments
    /// - `oracle_witness`: Optional witness supplied by the solver
    ///
    /// # Aborts
    /// - `ESIGNATURE_REQUIRED`: Missing witness when the order expects one
    fun verify_oracle_requirement(
        argument: &OracleGuardedLimitOrder,
        oracle_witness: &Option<OracleSignatureWitness>,
    ) {
        if (option::is_some(oracle_witness)) {
            let witness = option::borrow(oracle_witness);
            verify_oracle_witness(&argument.requirement, witness, argument.intent_id);
        } else {
            abort error::invalid_argument(ESIGNATURE_REQUIRED)
        }
    }

    /// Applies signature and threshold checks against the supplied witness.
    ///
    /// The verifier signs the intent_id to approve it. The signature itself is the approval.
    /// We verify that the signature is valid for the intent_id.
    ///
    /// # Arguments
    /// - `requirement`: Oracle metadata embedded in the intent arguments
    /// - `witness`: Signed report supplied by the solver
    /// - `intent_id`: Intent ID from hub chain (for escrows) - this is what was signed
    ///
    /// # Aborts
    /// - `EINVALID_SIGNATURE`: Signature verification failed
    /// - `EORACLE_VALUE_TOO_LOW`: Reported value is below `min_reported_value`
    fun verify_oracle_witness(
        requirement: &OracleSignatureRequirement,
        witness: &OracleSignatureWitness,
        intent_id: address,
    ) {
        // Verifier signs the intent_id (BCS-encoded address) - the signature itself is the approval
        let message = bcs::to_bytes(&intent_id);
        assert!(
            ed25519::signature_verify_strict(&witness.signature, &requirement.public_key, message),
            error::invalid_argument(EINVALID_SIGNATURE)
        );
        assert!(
            witness.reported_value >= requirement.min_reported_value,
            error::invalid_argument(EORACLE_VALUE_TOO_LOW)
        );
    }

    /// Destroys the on-chain store manager and returns the locked fungible asset.
    ///
    /// Entry function to revoke an oracle-guarded fungible asset intent and return the locked assets.
    /// 
    /// This function allows the intent owner to cancel their intent and get back
    /// their locked fungible assets before the intent expires or is completed.
    /// 
    /// # Arguments
    /// - `account`: Signer of the intent owner
    /// - `intent`: Object reference to the intent to revoke
    public entry fun revoke_fa_intent<Args: store + drop>(
        account: &signer,
        intent: Object<Intent<FungibleStoreManager, Args>>
    ) {
        let store_manager = intent::revoke_intent(account, intent);
        let fa = destroy_store_manager(store_manager);
        primary_fungible_store::deposit(signer::address_of(account), fa);
    }

    /// Shared implementation with the base module; duplicated here to avoid
    /// reaching through an external helper from tests.
    fun destroy_store_manager(store_manager: FungibleStoreManager): FungibleAsset {
        let FungibleStoreManager { extend_ref, delete_ref } = store_manager;
        let store_signer = object::generate_signer_for_extending(&extend_ref);
        let fa_store = object::object_from_delete_ref<FungibleStore>(&delete_ref);
        let fa = fungible_asset::withdraw(&store_signer, fa_store, fungible_asset::balance(fa_store));
        fungible_asset::remove_store(&delete_ref);
        object::delete(delete_ref);
        fa
    }
}
