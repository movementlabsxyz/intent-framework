#[test_only]
module aptos_intent::fa_intent_cross_chain_tests {
    use std::signer;
    use aptos_framework::timestamp;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_intent::fa_intent_cross_chain;

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(
        aptos_framework = @0x1,
        requestor = @0xcafe,
        solver = @0xdead
    )]
    /// Test: Cross-chain request intent fulfillment
    /// Verifies that a solver can fulfill a cross-chain request intent where the requestor
    /// has 0 tokens locked on the hub chain (tokens are in escrow on a different chain).
    /// This is Step 3 of the cross-chain escrow flow.
    fun test_fulfill_cross_chain_request_intent(
        aptos_framework: &signer,
        requestor: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Create test fungible assets for cross-chain swap
        // Source FA (locked on connected chain) and desired FA (requested on hub chain)
        let (source_metadata, _) = aptos_intent::fa_test_utils::register_and_mint_tokens(aptos_framework, requestor, 0);
        let (desired_metadata, _desired_mint_ref) = aptos_intent::fa_test_utils::register_and_mint_tokens(aptos_framework, solver, 100);
        
        // Requestor creates a cross-chain request intent (has 0 tokens locked)
        // Use a dummy intent_id for testing (in real scenarios this links cross-chain intents)
        let dummy_intent_id = @0x1234;
        let intent_address = fa_intent_cross_chain::create_cross_chain_request_intent(
            requestor,
            source_metadata,
            desired_metadata,
            100, // Wants 100 tokens from solver
            timestamp::now_seconds() + 3600,
            dummy_intent_id,
        );
        
        // Verify intent was created
        assert!(intent_address != @0x0);
        
        // Convert address to object reference (generic Object type)
        let intent_obj = object::address_to_object(intent_address);
        
        // Solver fulfills the intent using the entry function
        // Note: This calls start_fa_offering_session (unlocks 0 tokens), 
        // withdraws payment tokens, and finishes the session
        fa_intent_cross_chain::fulfill_cross_chain_request_intent(
            solver,
            intent_obj,
            100, // Provides 100 tokens
        );
        
        // Verify requestor received the tokens
        assert!(primary_fungible_store::balance(signer::address_of(requestor), desired_metadata) == 100);
        
        // Verify solver's balance decreased (100 - 100 = 0)
        assert!(primary_fungible_store::balance(signer::address_of(solver), desired_metadata) == 0);
    }

    #[test(
        aptos_framework = @0x1,
        requestor = @0xcafe,
        solver = @0xdead
    )]
    #[expected_failure(abort_code = 65537, location = aptos_intent::fa_intent)] // error::invalid_argument(EAMOUNT_NOT_MEET)
    /// Test: Cross-chain request intent fulfillment with insufficient amount
    /// Verifies that fulfillment fails when provided_amount < desired_amount.
    ///
    /// Expected behavior: Fulfillment fails with EAMOUNT_NOT_MEET when provided_amount < desired_amount.
    ///
    /// Actual validation is in fa_intent::finish_fa_receiving_session_with_event()
    /// which asserts: provided_amount >= argument.desired_amount
    fun test_fulfill_cross_chain_request_intent_insufficient_amount(
        aptos_framework: &signer,
        requestor: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Create test fungible assets for cross-chain swap
        let (source_metadata, _) = aptos_intent::fa_test_utils::register_and_mint_tokens(aptos_framework, requestor, 0);
        let (desired_metadata, _desired_mint_ref) = aptos_intent::fa_test_utils::register_and_mint_tokens(aptos_framework, solver, 100);
        
        // Requestor creates a cross-chain request intent wanting 1000 tokens
        let dummy_intent_id = @0x123;
        let intent_address = fa_intent_cross_chain::create_cross_chain_request_intent(
            requestor,
            source_metadata,
            desired_metadata,
            1000, // Wants 1000 tokens
            timestamp::now_seconds() + 3600,
            dummy_intent_id,
        );
        
        // Convert address to object reference
        let intent_obj = object::address_to_object(intent_address);
        
        // Solver tries to fulfill with insufficient amount (50 < 1000)
        // This should fail with EAMOUNT_NOT_MEET
        fa_intent_cross_chain::fulfill_cross_chain_request_intent(
            solver,
            intent_obj,
            50, // Provides only 50 tokens (insufficient! Needs 1000)
        );
    }

}

