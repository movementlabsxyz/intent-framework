/// Extension of the fungible asset intent flow that layers an oracle signature
/// requirement on top of the base limit-order mechanics.
///
/// Offerers still escrow a single fungible asset, but settlement succeeds only
/// when the solver supplies a signed report from an authorized oracle whose
/// reported value meets the threshold chosen by the creator.
module aptos_intent::fa_intent_with_oracle {
    use std::bcs;
    use std::error;
    use std::option::{Self as option, Option};
    use std::signer;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, FungibleStore};
    use aptos_framework::object::{Self, DeleteRef, ExtendRef, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_intent::intent::{Self, TradeSession, TradeIntent};
    use aptos_intent::intent_reservation::{Self, IntentReserved};
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
        desired_amount: u64,
        issuer: address,
        requirement: OracleSignatureRequirement,
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
        source_metadata: Object<Metadata>,
        source_amount: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        issuer: address,
        expiry_time: u64,
        min_reported_value: u64,
        revocable: bool,
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
    /// - `source_fungible_asset`: The asset being offered by the issuer
    /// - `desired_metadata`: Metadata handle of the asset the issuer wants to receive
    /// - `desired_amount`: Minimum amount of the desired asset that must be paid
    /// - `expiry_time`: Unix timestamp after which the intent can no longer be filled
    /// - `issuer`: Address of the intent creator
    /// - `requirement`: Oracle public key and minimum reported value used for verification
    /// - `revocable`: Whether the intent can be revoked by the owner
    /// - `intent_id`: The original intent ID from hub chain (for escrows) or same as intent_address (for regular intents)
    /// - `reservation`: Optional reservation specifying which solver can claim the escrow
    ///
    /// # Returns
    /// - `Object<TradeIntent<...>>`: Handle to the created oracle-guarded intent
    public fun create_fa_to_fa_intent_with_oracle_requirement(
        source_fungible_asset: FungibleAsset,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        issuer: address,
        requirement: OracleSignatureRequirement,
        revocable: bool,
        intent_id: address,
        reservation: Option<IntentReserved>,
    ): Object<TradeIntent<FungibleStoreManager, OracleGuardedLimitOrder>> {
        // Capture metadata and amount before depositing
        let source_metadata = fungible_asset::asset_metadata(&source_fungible_asset);
        let source_amount = fungible_asset::amount(&source_fungible_asset);
        
        let coin_store_ref = object::create_object(issuer);
        let extend_ref = object::generate_extend_ref(&coin_store_ref);
        let delete_ref = object::generate_delete_ref(&coin_store_ref);
        let transfer_ref = object::generate_transfer_ref(&coin_store_ref);
        let linear_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_ref, object::address_from_constructor_ref(&coin_store_ref));

        fungible_asset::create_store(&coin_store_ref, fungible_asset::metadata_from_asset(&source_fungible_asset));
        fungible_asset::deposit(
            object::object_from_constructor_ref<FungibleStore>(&coin_store_ref),
            source_fungible_asset
        );
        let intent_obj = intent::create_intent<FungibleStoreManager, OracleGuardedLimitOrder, OracleGuardedWitness>(
            FungibleStoreManager { extend_ref, delete_ref },
            OracleGuardedLimitOrder { desired_metadata, desired_amount, issuer, requirement },
            expiry_time,
            issuer,
            OracleGuardedWitness {},
            reservation,
            revocable,
        );

        // Emit event after creating intent so we have the intent address
        event::emit(OracleLimitOrderEvent {
            intent_address: object::object_address(&intent_obj),
            intent_id,  // Pass the intent ID from user (hub chain intent ID for escrows)
            source_metadata,
            source_amount,
            desired_metadata,
            desired_amount,
            issuer,
            expiry_time,
            min_reported_value: requirement.min_reported_value,
            revocable,
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
    /// - `TradeSession<OracleGuardedLimitOrder>`: "Hot potato" session tracking the intent arguments
    ///
    /// # Aborts
    /// - If the intent is reserved and the solver is not the authorized solver
    public fun start_fa_offering_session(
        solver: &signer,
        intent: Object<TradeIntent<FungibleStoreManager, OracleGuardedLimitOrder>>
    ): (FungibleAsset, TradeSession<OracleGuardedLimitOrder>) {
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
        session: TradeSession<OracleGuardedLimitOrder>,
        received_fa: FungibleAsset,
        oracle_witness_opt: Option<OracleSignatureWitness>,
    ) {
        let argument = intent::get_argument(&session);
        assert!(
            fungible_asset::metadata_from_asset(&received_fa) == argument.desired_metadata,
            error::invalid_argument(ENOT_DESIRED_TOKEN)
        );
        assert!(
            fungible_asset::amount(&received_fa) >= argument.desired_amount,
            error::invalid_argument(EAMOUNT_NOT_MEET),
        );

        verify_oracle_requirement(argument, &oracle_witness_opt);

        primary_fungible_store::deposit(argument.issuer, received_fa);
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
            verify_oracle_witness(&argument.requirement, witness);
        } else {
            abort error::invalid_argument(ESIGNATURE_REQUIRED)
        }
    }

    /// Applies signature and threshold checks against the supplied witness.
    ///
    /// # Arguments
    /// - `requirement`: Oracle metadata embedded in the intent arguments
    /// - `witness`: Signed report supplied by the solver
    ///
    /// # Aborts
    /// - `EINVALID_SIGNATURE`: Signature verification failed
    /// - `EORACLE_VALUE_TOO_LOW`: Reported value is below `min_reported_value`
    fun verify_oracle_witness(
        requirement: &OracleSignatureRequirement,
        witness: &OracleSignatureWitness,
    ) {
        let message = bcs::to_bytes(&witness.reported_value);
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
        intent: Object<TradeIntent<FungibleStoreManager, Args>>
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
