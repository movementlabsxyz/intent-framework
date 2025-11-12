#[test_only]
module mvmt_intent::fa_tests {
    use std::signer;
    use std::option;
    use aptos_framework::timestamp;
    use aptos_framework::fungible_asset;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use mvmt_intent::fa_intent;
    use mvmt_intent::test_utils;

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        solver = @0xdead
    )]
    /// Test: Fungible Asset Session with success
    /// Verifies that fungible asset orders can be created and events are emitted.
    /// Verifies that solvers can unlock fungible assets from intents and start trading sessions.
    fun test_fa_limit_order(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ) {
        let (offered_fa_type, _mint_ref_2) = test_utils::register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _desired_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, solver, 25);
        
        // Creator creates intent to trade 50 offered tokens for 25 desired tokens
        let intent = fa_intent::create_fa_to_fa_intent(
            primary_fungible_store::withdraw(offerer, offered_fa_type, 50),
            1, // offered_chain_id
            desired_fa_type,
            25,
            1, // desired_chain_id
            timestamp::now_seconds() + 3600,
            signer::address_of(offerer),
            option::none(),
            true, // revocable
            option::none(), // No cross-chain intent_id for regular intents
        );
        // Verify intent was created
        assert!(object::object_address(&intent) != @0x0);

        // Solver 
        // 1. starts the session and unlocks the tokens
        let (unlocked_fa, session) = fa_intent::start_fa_offering_session(solver, intent);
        // Verify solver got the correct amount from the session
        assert!(fungible_asset::amount(&unlocked_fa) == 50);
        assert!(fungible_asset::metadata_from_asset(&unlocked_fa) == object::convert(offered_fa_type));
        // Solver deposits the unlocked tokens to their own account
        primary_fungible_store::deposit(signer::address_of(solver), unlocked_fa);
        // 2. Solver provides the desired tokens
        let desired_fa = primary_fungible_store::withdraw(solver, desired_fa_type, 25);
        // 3. Finish the session (this will handle transferring tokens to creator)
        fa_intent::finish_fa_receiving_session(session, desired_fa);
        
        // Verify balances have been correctly settled
        assert!(primary_fungible_store::balance(signer::address_of(solver), offered_fa_type) == 50, 5);
        assert!(primary_fungible_store::balance(signer::address_of(offerer), desired_fa_type) == 25, 3);
    }

    #[test(
        aptos_framework = @0x1,
        offerer1 = @0xcafe,
        offerer2 = @0xbeef,
        solver = @0xdead
    )]
    /// Test: Solver matches two opposing limit orders and settles both intents.
    fun test_fa_limit_order_cross_match(
        aptos_framework: &signer,
        offerer1: &signer,
        offerer2: &signer,
        solver: &signer,
    ) {
        let (fa1_metadata, _) = test_utils::register_and_mint_tokens(aptos_framework, offerer1, 100);
        let (fa2_metadata, _) = test_utils::register_and_mint_tokens(aptos_framework, offerer2, 100);

        // Offerer1 deposits 30 of FA1 requesting 15 of FA2.
        let intent1 = fa_intent::create_fa_to_fa_intent(
            primary_fungible_store::withdraw(offerer1, fa1_metadata, 30),
            1, // offered_chain_id
            fa2_metadata,
            15,
            1, // desired_chain_id
            timestamp::now_seconds() + 3600,
            signer::address_of(offerer1),
            option::none(),
            true, // revocable
            option::none(), // No cross-chain intent_id for regular intents
        );

        // Offerer2 deposits 15 of FA2 requesting 30 of FA1.
        let intent2 = fa_intent::create_fa_to_fa_intent(
            primary_fungible_store::withdraw(offerer2, fa2_metadata, 15),
            1, // offered_chain_id
            fa1_metadata,
            30,
            1, // desired_chain_id
            timestamp::now_seconds() + 3600,
            signer::address_of(offerer2),
            option::none(),
            true, // revocable
            option::none(), // No cross-chain intent_id for regular intents
        );

        // Solver unlocks both intents to gather the offered assets.
        let (solver_fa1, session1) = fa_intent::start_fa_offering_session(solver, intent1);
        primary_fungible_store::deposit(signer::address_of(solver), solver_fa1);

        let (solver_fa2, session2) = fa_intent::start_fa_offering_session(solver, intent2);
        primary_fungible_store::deposit(signer::address_of(solver), solver_fa2);

        // Solver repays 15 FA2 to fulfill offerer1's request and closes their session.
        let payment_fa2 = primary_fungible_store::withdraw(solver, fa2_metadata, 15);
        fa_intent::finish_fa_receiving_session(session1, payment_fa2);

        // Solver repays 30 FA1 to fulfill offerer2's request and closes their session.
        let payment_fa1 = primary_fungible_store::withdraw(solver, fa1_metadata, 30);
        fa_intent::finish_fa_receiving_session(session2, payment_fa1);

        // Each offerer swapped into their desired asset; solver ends with no net position.
        assert!(primary_fungible_store::balance(signer::address_of(offerer1), fa1_metadata) == 70);
        assert!(primary_fungible_store::balance(signer::address_of(offerer1), fa2_metadata) == 15);
        assert!(primary_fungible_store::balance(signer::address_of(offerer2), fa2_metadata) == 85);
        assert!(primary_fungible_store::balance(signer::address_of(offerer2), fa1_metadata) == 30);
        assert!(primary_fungible_store::balance(signer::address_of(solver), fa1_metadata) == 0);
        assert!(primary_fungible_store::balance(signer::address_of(solver), fa2_metadata) == 0);
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        solver = @0xdead
    )]
    /// Test: Fungible Asset Intent Revocation Success (revocable = true)
    /// Verifies that revocable fungible asset intents can be cancelled and tokens recovered.
    fun test_revoke_fa_intent_success(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ) {
        let (offered_fa_type, _) = test_utils::register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _) = test_utils::register_and_mint_tokens(aptos_framework, solver, 0);
        
        // Creator creates intent to trade 50 offered tokens for 25 desired tokens
        let intent = fa_intent::create_fa_to_fa_intent(
            primary_fungible_store::withdraw(offerer, offered_fa_type, 50),
            1, // offered_chain_id
            desired_fa_type,
            25,
            1, // desired_chain_id
            timestamp::now_seconds() + 3600,
            signer::address_of(offerer),
            option::none(),
            true, // revocable
            option::none(), // No cross-chain intent_id for regular intents
        );
        // Check balance before revocation
        assert!(primary_fungible_store::balance(signer::address_of(offerer), offered_fa_type) == 50);
        
        // Revoke the intent
        fa_intent::revoke_fa_intent(offerer, intent);
        
        // Check balance after revocation - should be back to 100
        assert!(primary_fungible_store::balance(signer::address_of(offerer), offered_fa_type) == 100);
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        solver = @0xdead
    )]
    #[expected_failure(abort_code = 65537, location = fa_intent)] // error::invalid_argument(EAMOUNT_NOT_MEET)
    /// Test: Insufficient Tokens Error
    /// Verifies that the intent framework properly handles cases where the solver provides insufficient tokens to complete the trade.
    fun test_fa_limit_order_insufficient_solver_payment(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ) {
        let (offered_fa_type, _) = test_utils::register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _) = test_utils::register_and_mint_tokens(aptos_framework, solver, 5); // Only 5 tokens available
        
        // Creator creates intent to trade 50 offered tokens for 25 desired tokens
        let intent = fa_intent::create_fa_to_fa_intent(
            primary_fungible_store::withdraw(offerer, offered_fa_type, 50),
            1, // offered_chain_id
            desired_fa_type,
            25, // Wants 25 but solver only has 5
            1, // desired_chain_id
            timestamp::now_seconds() + 3600,
            signer::address_of(offerer),
            option::none(),
            true, // revocable
            option::none(), // No cross-chain intent_id for regular intents
        );
        
        // Solver starts the session and unlocks the 50 offered tokens
        let (unlocked_fa, session) = fa_intent::start_fa_offering_session(solver, intent);
        
        // Solver deposits the unlocked tokens to their account
        primary_fungible_store::deposit(signer::address_of(solver), unlocked_fa);
        
        // Solver withdraws only 5 desired tokens (but intent requires 25)
        let desired_fa = primary_fungible_store::withdraw(solver, desired_fa_type, 5);
        
        // Solver tries to finish the session with insufficient tokens - this should fail
        fa_intent::finish_fa_receiving_session(session, desired_fa);
    }

}
