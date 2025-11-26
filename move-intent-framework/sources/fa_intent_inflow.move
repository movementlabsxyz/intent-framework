module mvmt_intent::fa_intent_inflow {
    use std::signer;
    use std::option;
    use std::error;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self as object, Object};
    use aptos_framework::fungible_asset::{FungibleAsset, Metadata};
    use mvmt_intent::fa_intent::{Self, FungibleStoreManager, FungibleAssetLimitOrder};
    use mvmt_intent::intent::{Self as intent, TradeIntent};
    use mvmt_intent::intent_reservation;

    /// The solver signature is invalid and cannot be verified.
    const EINVALID_SIGNATURE: u64 = 2;

    // ============================================================================
    // SHARED UTILITIES
    // ============================================================================

    /// Creates a draft intent for cross-chain request.
    /// This is step 1 of the reserved intent flow:
    /// 1. Requester creates draft using this function (off-chain)
    /// 2. Solver signs the draft and returns signature (off-chain)
    /// 3. Requester calls create_inflow_request_intent with the signature (on-chain)
    public fun create_cross_chain_draft_intent(
        offered_metadata: Object<Metadata>,
        offered_amount: u64,
        offered_chain_id: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        desired_chain_id: u64,
        expiry_time: u64,
        requester: address
    ): intent_reservation::IntentDraft {
        intent_reservation::create_draft_intent(
            offered_metadata,
            offered_amount,
            offered_chain_id,
            desired_metadata,
            desired_amount,
            desired_chain_id,
            expiry_time,
            requester
        )
    }

    // ============================================================================
    // INFLOW REQUEST-INTENT FUNCTIONS
    // ============================================================================

    /// Entry function for solver to fulfill an inflow request-intent.
    ///
    /// Inflow intents have tokens locked on the connected chain (in escrow) and request tokens on the hub.
    /// The solver provides the desired tokens to the requester on the hub chain.
    /// No verifier signature is required for inflow intents.
    ///
    /// # Arguments
    /// - `solver`: Signer fulfilling the intent
    /// - `intent`: Object reference to the inflow intent to fulfill (FungibleAssetLimitOrder)
    /// - `payment_amount`: Amount of tokens to provide
    public entry fun fulfill_inflow_request_intent(
        solver: &signer,
        intent: Object<TradeIntent<FungibleStoreManager, FungibleAssetLimitOrder>>,
        payment_amount: u64
    ) {
        let intent_address = object::object_address(&intent);
        let solver_address = signer::address_of(solver);

        // 1. Start the session (this unlocks 0 tokens, but creates the session)
        let (unlocked_fa, session) = fa_intent::start_fa_offering_session(
            solver, intent
        );

        // Deposit the unlocked tokens (which are 0 for inflow intents)
        primary_fungible_store::deposit(solver_address, unlocked_fa);

        // 2. Infer desired metadata from the intent's stored argument
        let argument = intent::get_argument(&session);
        let desired_metadata = fa_intent::get_desired_metadata(argument);

        // 3. Withdraw the desired tokens from solver's account
        let payment_fa =
            primary_fungible_store::withdraw(solver, desired_metadata, payment_amount);

        // 4. Finish the session by providing the payment tokens and emit fulfillment event
        fa_intent::finish_fa_receiving_session_with_event(
            session,
            payment_fa,
            intent_address,
            solver_address
        );
    }

    /// Creates an inflow request-intent and returns the intent object.
    ///
    /// This is the core implementation that both the entry function and tests use.
    ///
    /// # Arguments
    /// - `account`: Signer of the requester creating the intent
    /// - `offered_metadata`: Metadata of the token type being offered (locked on connected chain)
    /// - `offered_amount`: Amount of tokens offered (locked in escrow on connected chain)
    /// - `offered_chain_id`: Chain ID where the escrow is created (connected chain)
    /// - `desired_metadata`: Metadata of the desired token type
    /// - `desired_amount`: Amount of desired tokens
    /// - `desired_chain_id`: Chain ID of the hub chain (where this intent is created)
    /// - `expiry_time`: Unix timestamp when intent expires
    /// - `intent_id`: Intent ID for cross-chain linking
    /// - `solver`: Address of the solver authorized to fulfill this intent (must be registered)
    /// - `solver_signature`: Ed25519 signature from the solver authorizing this intent
    ///
    /// # Returns
    /// - `Object<TradeIntent<FungibleStoreManager, FungibleAssetLimitOrder>>`: The created intent object
    ///
    /// # Aborts
    /// - `ESOLVER_NOT_REGISTERED`: Solver is not registered in the solver registry
    /// - `EINVALID_SIGNATURE`: Signature verification failed
    public fun create_inflow_request_intent(
        account: &signer,
        offered_metadata: Object<Metadata>,
        offered_amount: u64,
        offered_chain_id: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        desired_chain_id: u64,
        expiry_time: u64,
        intent_id: address,
        solver: address,
        solver_signature: vector<u8>
    ): Object<TradeIntent<FungibleStoreManager, FungibleAssetLimitOrder>> {
        // Withdraw 0 tokens of offered type (no tokens locked on hub chain, just requesting for cross-chain swap)
        let fa: FungibleAsset =
            primary_fungible_store::withdraw(account, offered_metadata, 0);

        // Verify solver signature and create reservation using the solver registry
        let intent_to_sign =
            intent_reservation::new_intent_to_sign(
                offered_metadata,
                offered_amount,
                offered_chain_id,
                desired_metadata,
                desired_amount,
                desired_chain_id,
                expiry_time,
                signer::address_of(account),
                solver
            );

        // Use verify_and_create_reservation_from_registry to look up public key from registry
        let reservation_result =
            intent_reservation::verify_and_create_reservation_from_registry(
                intent_to_sign, solver_signature
            );
        // Fail if signature verification failed - cross-chain intents must be reserved
        assert!(
            option::is_some(&reservation_result),
            error::invalid_argument(EINVALID_SIGNATURE)
        );

        fa_intent::create_fa_to_fa_intent(
            fa,
            offered_chain_id, // where escrow is created
            desired_metadata,
            desired_amount,
            desired_chain_id, // hub chain where this intent is created
            expiry_time,
            signer::address_of(account),
            reservation_result, // Reserved for specific solver
            false, // CRITICAL: All parts of a cross-chain intent MUST be non-revocable (including the hub request-intent)
            // Ensures consistent safety guarantees for verifiers across chains
            option::some(intent_id) // Store the cross-chain intent_id for fulfillment event
        )
    }

    /// Entry function to create an inflow request-intent.
    ///
    /// Inflow intents have tokens locked on the connected chain (in escrow) and request tokens on the hub.
    /// The solver's public key is looked up from the on-chain solver registry.
    ///
    /// For argument descriptions and abort conditions, see `create_inflow_request_intent`.
    public entry fun create_inflow_request_intent_entry(
        account: &signer,
        offered_metadata: Object<Metadata>,
        offered_amount: u64,
        offered_chain_id: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        desired_chain_id: u64,
        expiry_time: u64,
        intent_id: address,
        solver: address,
        solver_signature: vector<u8>
    ) {
        let _intent_obj =
            create_inflow_request_intent(
                account,
                offered_metadata,
                offered_amount,
                offered_chain_id,
                desired_metadata,
                desired_amount,
                desired_chain_id,
                expiry_time,
                intent_id,
                solver,
                solver_signature
            );
    }
}
