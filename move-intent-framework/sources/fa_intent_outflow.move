module mvmt_intent::fa_intent_outflow {
    use std::signer;
    use std::option;
    use std::error;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::{Self as fungible_asset, FungibleAsset, Metadata};
    use mvmt_intent::fa_intent_with_oracle;
    use mvmt_intent::intent::TradeIntent;
    use mvmt_intent::intent_reservation;
    use aptos_std::ed25519;

    /// The solver signature is invalid and cannot be verified.
    const EINVALID_SIGNATURE: u64 = 2;
    /// The requester address on the connected chain is invalid (zero address).
    const EINVALID_REQUESTER_ADDRESS: u64 = 3;

    // ============================================================================
    // SHARED UTILITIES
    // ============================================================================

    /// Creates a draft intent for cross-chain request.
    /// This is step 1 of the reserved intent flow:
    /// 1. Requester creates draft using this function (off-chain)
    /// 2. Solver signs the draft and returns signature (off-chain)
    /// 3. Requester calls create_outflow_request_intent with the signature (on-chain)
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
    // OUTFLOW REQUEST-INTENT FUNCTIONS
    // ============================================================================

    /// Entry function for solver to fulfill an outflow request-intent.
    ///
    /// Outflow intents have tokens locked on the hub chain and request tokens on the connected chain.
    /// The solver must first transfer tokens on the connected chain, then the verifier approves that transaction.
    /// The solver receives the locked tokens from the hub as reward, and provides 0 tokens as payment
    /// (since desired_amount = 0 on hub for outflow intents).
    /// Verifier signature is required - it proves the solver transferred tokens on the connected chain.
    ///
    /// # Arguments
    /// - `solver`: Signer fulfilling the intent
    /// - `intent`: Object reference to the outflow intent to fulfill (OracleGuardedLimitOrder)
    /// - `verifier_signature_bytes`: Verifier's Ed25519 signature as bytes (signs the intent_id, proves connected chain transfer)
    public entry fun fulfill_outflow_request_intent(
        solver: &signer,
        intent: Object<TradeIntent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>>,
        verifier_signature_bytes: vector<u8>
    ) {
        let solver_address = signer::address_of(solver);

        // 1. Start the session (unlocks actual tokens that were locked on hub - these are the solver's reward)
        let (unlocked_fa, session) =
            fa_intent_with_oracle::start_fa_offering_session(solver, intent);

        // 2. Infer payment metadata from the unlocked tokens BEFORE depositing (FungibleAsset doesn't have copy)
        // For outflow, desired_metadata matches offered_metadata (placeholder), so we use unlocked tokens' metadata
        let payment_metadata = fungible_asset::asset_metadata(&unlocked_fa);

        // 3. Deposit unlocked tokens to solver (they get the locked tokens as payment for their work)
        primary_fungible_store::deposit(solver_address, unlocked_fa);

        // 4. Withdraw 0 tokens as payment (desired_amount = 0 on hub for outflow)
        // The actual desired tokens are on the connected chain, which the solver already transferred
        let solver_payment = primary_fungible_store::withdraw(
            solver, payment_metadata, 0
        );

        // 5. Convert signature bytes to ed25519::Signature
        let verifier_signature =
            ed25519::new_signature_from_bytes(verifier_signature_bytes);

        // 6. Create verifier witness - signature itself is the approval
        // The intent_id is stored in the session argument and will be used automatically
        // by finish_fa_receiving_session_with_oracle for signature verification
        let witness =
            fa_intent_with_oracle::new_oracle_signature_witness(
                0, // reported_value: signature verification is what matters, this is just metadata
                verifier_signature
            );

        // 7. Complete the intent with verifier signature (proves connected chain transfer happened)
        // The finish function will verify the signature against the intent_id stored in the argument
        // Payment amount is 0, which matches desired_amount = 0 for outflow intents
        fa_intent_with_oracle::finish_fa_receiving_session_with_oracle(
            session,
            solver_payment,
            option::some(witness)
        );
    }

    /// Creates an outflow request-intent and returns the intent object.
    ///
    /// This is the core implementation that both the entry function and tests use.
    ///
    /// # Arguments
    /// - `requester_signer`: Signer of the requester creating the intent
    /// - `offered_metadata`: Metadata of the token type being offered (locked on hub chain)
    /// - `offered_amount`: Amount of tokens to withdraw and lock on hub chain
    /// - `offered_chain_id`: Chain ID of the hub chain (where tokens are locked)
    /// - `desired_metadata`: Metadata of the desired token type
    /// - `desired_amount`: Amount of desired tokens
    /// - `desired_chain_id`: Chain ID where tokens are desired (connected chain)
    /// - `expiry_time`: Unix timestamp when intent expires
    /// - `intent_id`: Intent ID for cross-chain linking
    /// - `requester_address_connected_chain`: Address on connected chain where solver should send tokens
    /// - `verifier_public_key`: Public key of the verifier that will approve the connected chain transaction (32 bytes)
    /// - `solver`: Address of the solver authorized to fulfill this intent (must be registered)
    /// - `solver_signature`: Ed25519 signature from the solver authorizing this intent
    ///
    /// # Returns
    /// - `Object<TradeIntent<FungibleStoreManager, OracleGuardedLimitOrder>>`: The created intent object
    ///
    /// # Aborts
    /// - `ESOLVER_NOT_REGISTERED`: Solver is not registered in the solver registry
    /// - `EINVALID_SIGNATURE`: Signature verification failed
    /// - `EINVALID_REQUESTER_ADDRESS`: requester_address_connected_chain is zero address (0x0)
    public fun create_outflow_request_intent(
        requester_signer: &signer,
        offered_metadata: Object<Metadata>,
        offered_amount: u64,
        offered_chain_id: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        desired_chain_id: u64,
        expiry_time: u64,
        intent_id: address,
        requester_address_connected_chain: address,
        verifier_public_key: vector<u8>, // 32 bytes
        solver: address,
        solver_signature: vector<u8>
    ): Object<TradeIntent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>> {
        // Validate requester_address_connected_chain is not zero address
        // Outflow intents require a valid address on the connected chain where the solver should send tokens
        assert!(
            requester_address_connected_chain != @0x0,
            error::invalid_argument(EINVALID_REQUESTER_ADDRESS)
        );

        // Withdraw actual tokens from requester (locked on hub chain for outflow)
        let fa: FungibleAsset =
            primary_fungible_store::withdraw(
                requester_signer, offered_metadata, offered_amount
            );

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
                signer::address_of(requester_signer),
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

        // Build ed25519::UnvalidatedPublicKey from bytes
        let verifier_pk =
            ed25519::new_unvalidated_public_key_from_bytes(verifier_public_key);

        // Create oracle requirement: signature itself is the approval, min_reported_value is 0
        // (the signature verification is what matters, not the reported_value)
        let requirement =
            fa_intent_with_oracle::new_oracle_signature_requirement(
                0, // min_reported_value: signature verification is what matters, this check always passes
                verifier_pk
            );

        // For outflow intents on hub chain:
        // - offered_amount = actual amount locked (tokens locked on hub)
        // - desired_amount = original desired_amount (for the connected chain specified by desired_chain_id)
        // - desired_metadata = placeholder (use same as offered_metadata for payment check)
        // The payment validation will check if desired_chain_id != offered_chain_id and use 0 for payment on hub
        let placeholder_metadata = fungible_asset::asset_metadata(&fa);

        fa_intent_with_oracle::create_fa_to_fa_intent_with_oracle_requirement(
            fa,
            offered_chain_id, // Chain ID where offered tokens are located (hub chain)
            placeholder_metadata, // Use same metadata as locked tokens (placeholder for payment check)
            desired_amount, // Original desired_amount (for the connected chain) - payment validation will use 0 on hub
            desired_chain_id, // Chain ID where desired tokens are located (connected chain)
            expiry_time,
            signer::address_of(requester_signer),
            requirement,
            false, // CRITICAL: All parts of a cross-chain intent MUST be non-revocable
            // Ensures consistent safety guarantees for verifiers across chains
            intent_id,
            option::some(requester_address_connected_chain), // Store where solver should send tokens on connected chain
            reservation_result // Reserved for specific solver
        )
    }

    /// Entry function to create an outflow request-intent.
    ///
    /// Outflow intents have tokens locked on the hub chain and request tokens on the connected chain.
    /// This function uses `OracleGuardedLimitOrder` (requires verifier signature) and withdraws actual
    /// tokens from the requester (locked on hub).
    ///
    /// For argument descriptions and abort conditions, see `create_outflow_request_intent`.
    public entry fun create_outflow_request_intent_entry(
        requester_signer: &signer,
        offered_metadata: Object<Metadata>,
        offered_amount: u64,
        offered_chain_id: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        desired_chain_id: u64,
        expiry_time: u64,
        intent_id: address,
        requester_address_connected_chain: address,
        verifier_public_key: vector<u8>, // 32 bytes
        solver: address,
        solver_signature: vector<u8>
    ) {
        let _intent_obj =
            create_outflow_request_intent(
                requester_signer,
                offered_metadata,
                offered_amount,
                offered_chain_id,
                desired_metadata,
                desired_amount,
                desired_chain_id,
                expiry_time,
                intent_id,
                requester_address_connected_chain,
                verifier_public_key,
                solver,
                solver_signature
            );
    }
}
