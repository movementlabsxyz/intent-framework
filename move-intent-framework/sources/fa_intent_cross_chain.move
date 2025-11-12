module mvmt_intent::fa_intent_cross_chain {
    use std::signer;
    use std::option;
    use std::error;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self as object, Object};
    use aptos_framework::fungible_asset::{FungibleAsset, Metadata};
    use mvmt_intent::fa_intent::{
        Self,
        FungibleStoreManager,
        FungibleAssetLimitOrder,
    };
    use mvmt_intent::intent::{Self as intent, TradeIntent};
    use mvmt_intent::intent_reservation;

    /// The solver signature is invalid and cannot be verified.
    const EINVALID_SIGNATURE: u64 = 2;

    // ============================================================================
    // GENERIC CROSS-CHAIN INTENT FUNCTIONS
    // ============================================================================

    /// Creates a draft intent for cross-chain request (source_amount = 0).
    /// This is step 1 of the reserved intent flow:
    /// 1. User creates draft using this function (off-chain)
    /// 2. Solver signs the draft and returns signature (off-chain)
    /// 3. User calls create_cross_chain_request_intent_entry with the signature (on-chain)
    public fun create_cross_chain_draft_intent(
        source_metadata: Object<Metadata>,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        issuer: address,
    ): intent_reservation::IntentDraft {
        intent_reservation::create_draft_intent(
            source_metadata,
            0, // source_amount is 0 for cross-chain request intents
            desired_metadata,
            desired_amount,
            expiry_time,
            issuer,
        )
    }

    /// Entry function to create a cross-chain request intent using the solver registry.
    /// The solver's public key is looked up from the on-chain registry.
    ///
    /// # Arguments
    /// - `account`: Signer creating the intent
    /// - `source_metadata`: Metadata of the token type being offered (locked on another chain)
    /// - `desired_metadata`: Metadata of the desired token type
    /// - `desired_amount`: Amount of desired tokens
    /// - `expiry_time`: Unix timestamp when intent expires
    /// - `intent_id`: Intent ID for cross-chain linking
    /// - `connected_chain_id`: Chain ID where the escrow will be created (must match verifier config)
    /// - `solver`: Address of the solver authorized to fulfill this intent (must be registered)
    /// - `solver_signature`: Ed25519 signature from the solver authorizing this intent
    /// 
    /// # Aborts
    /// - `ESOLVER_NOT_REGISTERED`: Solver is not registered in the solver registry
    /// - `EINVALID_SIGNATURE`: Signature verification failed
    /// 
    /// # Note
    /// This intent is special: it has 0 tokens locked because tokens are in escrow elsewhere.
    /// This function accepts any fungible asset metadata, enabling cross-chain swaps with any FA pair.
    /// Cross-chain request intents MUST be reserved to ensure solver commitment across chains.
    /// The solver must be registered in the solver registry before calling this function.
    /// The connected_chain_id specifies which chain the escrow will be created on, allowing the verifier
    /// to validate that escrows are created on the correct chain.
    public entry fun create_cross_chain_request_intent_entry(
        account: &signer,
        source_metadata: Object<Metadata>,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        intent_id: address,
        connected_chain_id: u64,
        solver: address,
        solver_signature: vector<u8>,
    ) {
        // Withdraw 0 tokens of source type (no tokens locked, just requesting for cross-chain swap)
        let fa: FungibleAsset = primary_fungible_store::withdraw(account, source_metadata, 0);
        
        // Verify solver signature and create reservation using the solver registry
        // For cross-chain intents, source_amount is 0 (tokens are on another chain)
        let intent_to_sign = intent_reservation::new_intent_to_sign(
            source_metadata,
            0, // source_amount is 0 for cross-chain request intents
            desired_metadata,
            desired_amount,
            expiry_time,
            signer::address_of(account),
            solver,
        );
        
        // Use verify_and_create_reservation_from_registry to look up public key from registry
        let reservation_result = intent_reservation::verify_and_create_reservation_from_registry(
            intent_to_sign,
            solver_signature,
        );
        // Fail if signature verification failed - cross-chain intents must be reserved
        assert!(option::is_some(&reservation_result), error::invalid_argument(EINVALID_SIGNATURE));
        
        let _intent_obj = fa_intent::create_fa_to_fa_intent(
            fa,
            desired_metadata,
            desired_amount,
            expiry_time,
            signer::address_of(account),
            reservation_result, // Reserved for specific solver
            false, // 🔒 CRITICAL: All parts of a cross-chain intent MUST be non-revocable (including the hub request intent)
                   // Ensures consistent safety guarantees for verifiers across chains
            option::some(intent_id), // Store the cross-chain intent_id for fulfillment event
            option::some(connected_chain_id), // Store the connected chain ID for escrow validation
        );
        
        // Event is already emitted by create_fa_to_fa_intent with the correct intent_id
        // Intent address can be obtained from the LimitOrderEvent if needed
    }

    /// Entry function for solver to fulfill a cross-chain request intent.
    /// 
    /// This function:
    /// 1. Starts the session (unlocks 0 tokens since cross-chain intent has tokens locked on different chain)
    /// 2. Infers desired token metadata from the intent
    /// 3. Provides the desired tokens to the intent creator
    /// 4. Finishes the session to complete the intent
    /// 
    /// This is used for cross-chain swaps where tokens are locked in escrow on a different chain.
    /// 
    /// # Arguments
    /// - `solver`: Signer fulfilling the intent
    /// - `intent`: Object reference to the intent to fulfill
    /// - `payment_amount`: Amount of tokens to provide
    public entry fun fulfill_cross_chain_request_intent(
        solver: &signer,
        intent: Object<TradeIntent<FungibleStoreManager, FungibleAssetLimitOrder>>,
        payment_amount: u64,
    ) {
        let intent_address = object::object_address(&intent);
        let solver_address = signer::address_of(solver);
        
        // 1. Start the session (this unlocks 0 tokens, but creates the session)
        let (unlocked_fa, session) = fa_intent::start_fa_offering_session(solver, intent);
        
        // Deposit the unlocked tokens (which are 0 for cross-chain intents)
        primary_fungible_store::deposit(solver_address, unlocked_fa);
        
        // 2. Infer desired metadata from the intent's stored argument
        let argument = intent::get_argument(&session);
        let desired_metadata = fa_intent::get_desired_metadata(argument);
        
        // 3. Withdraw the desired tokens from solver's account
        let payment_fa = primary_fungible_store::withdraw(solver, desired_metadata, payment_amount);
        
        // 4. Finish the session by providing the payment tokens and emit fulfillment event
        fa_intent::finish_fa_receiving_session_with_event(session, payment_fa, intent_address, solver_address);
    }
}

