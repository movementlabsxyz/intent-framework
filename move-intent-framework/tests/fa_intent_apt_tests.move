#[test_only]
module aptos_intent::fa_intent_apt_tests {
    use std::signer;
    use std::option;
    use aptos_framework::timestamp;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_intent::fa_intent_apt;

    // ============================================================================
    // TESTS
    // ============================================================================

    // DO NOT DELETE - This test is kept to document the limitation
    // 
    // This test FAILS because:
    // 1. create_cross_chain_request_intent() is hardcoded to use APT metadata
    // 2. In Move unit tests, coin::paired_metadata<AptosCoin>() returns None
    // 3. The function cannot be tested with generic tokens in unit tests
    //
    // Actual cross-chain fulfillment is verified via submit-cross-chain-intent.sh (E2E test)
    #[test(
        requestor = @0xcafe,
        solver = @0xdead
    )]
    /// Test: Cross-chain request intent fulfillment
    /// Verifies that a solver can fulfill a cross-chain request intent where the requestor
    /// has 0 tokens locked on the hub chain (tokens are in escrow on a different chain).
    /// This is Step 3 of the cross-chain escrow flow.
    fun test_fulfill_cross_chain_request_intent(
        requestor: &signer,
        solver: &signer,
    ) {
        let aptos_metadata_opt = aptos_framework::coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        assert!(option::is_some(&aptos_metadata_opt), 9001);
        let aptos_metadata = option::destroy_some(aptos_metadata_opt);
        
        // Requestor creates a cross-chain request intent (has 0 tokens locked)
        // Use a dummy intent_id for testing (in real scenarios this links cross-chain intents)
        let dummy_intent_id = @0x123;
        let intent_address = fa_intent_apt::create_cross_chain_request_intent(
            requestor,
            1000, // Wants 1000 tokens from solver
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
        fa_intent_apt::fulfill_cross_chain_request_intent(
            solver,
            intent_obj,
            1000, // Provides 1000 tokens
        );
        
        // Verify requestor received the tokens
        assert!(primary_fungible_store::balance(signer::address_of(requestor), aptos_metadata) == 1000);
        
        // Verify solver's balance decreased
        assert!(primary_fungible_store::balance(signer::address_of(solver), aptos_metadata) == 999000);
    }

}

