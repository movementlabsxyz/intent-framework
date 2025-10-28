// Integration-focused tests that exercise the entry functions end-to-end.
// These complement `fa_tests.move` by validating solver/offerer
// transactions interact correctly through `PendingIntent` and shared state.
#[test_only]
module aptos_intent::fa_entryflow_tests {
    use std::signer;
    use std::option;

    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    use aptos_intent::fa_intent::{Self, FungibleAssetLimitOrder, FungibleStoreManager};
    use aptos_intent::intent;
    use aptos_intent::fa_test_utils::register_and_mint_tokens;

    #[test_only]
    struct PendingIntent has key {
        intent: object::Object<intent::TradeIntent<FungibleStoreManager, FungibleAssetLimitOrder>>,
    }

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    #[test_only]
    /// Offerer transaction: move offered tokens into an intent and track the resulting object.
    public entry fun offerer_submit_limit_order(
        offerer: &signer,
        offered_fa: object::Object<Metadata>,
        source_amount: u64,
        desired_fa: object::Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
    ) {
        let offerer_addr = signer::address_of(offerer);
        assert!(!exists<PendingIntent>(offerer_addr));

        let source_fa = primary_fungible_store::withdraw(offerer, offered_fa, source_amount);
        // Preserve the created intent so the solver can access it later.
        let intent = fa_intent::create_fa_to_fa_intent(
            source_fa,
            desired_fa,
            desired_amount,
            expiry_time,
            offerer_addr,
            option::none(),
            true, // revocable
        );

        move_to(offerer, PendingIntent { intent });
    }

    #[test_only]
    /// Solver transaction: consume the stored intent, settle the trade, and release the object.
    public entry fun solver_fill_limit_order(
        solver: &signer,
        offerer_addr: address,
        desired_fa: object::Object<Metadata>,
        desired_amount: u64,
    ) acquires PendingIntent {
        let PendingIntent { intent } = move_from<PendingIntent>(offerer_addr);

        // Solver 1. starts the session and unlocks the tokens from the offerer's intent.
        let (unlocked_fa, session) = fa_intent::start_fa_offering_session(solver, intent);
        // Solver deposits the unlocked tokens to their own account before providing the desired asset.
        primary_fungible_store::deposit(signer::address_of(solver), unlocked_fa);

        // Solver 2. withdraws the desired asset from their account to complete the trade.
        let desired_asset = primary_fungible_store::withdraw(solver, desired_fa, desired_amount);
        // Solver 3. finishes the session, which transfers the desired tokens to the creator and closes the intent.
        fa_intent::finish_fa_receiving_session(session, desired_asset);
    }

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        solver = @0xdead
    )]
    /// Integration-style test exercising user and solver transactions end-to-end.
    fun test_fa_limit_order(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ) acquires PendingIntent {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        // Each actor starts with 100 tokens of their respective asset.
        let (offered_fa, _) = register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa, _) = register_and_mint_tokens(aptos_framework, solver, 100);

        let expiry_time = timestamp::now_seconds() + 3600;

        // Offerer creates the intent by locking 50 of their tokens against a request for 25 desired tokens.
        offerer_submit_limit_order(offerer, offered_fa, 50, desired_fa, 25, expiry_time);
        assert!(exists<PendingIntent>(signer::address_of(offerer)));
        // Assert that the offerer's balance is now 50.
        assert!(primary_fungible_store::balance(signer::address_of(offerer), offered_fa) == 50);

        // Solver unlocks the offered tokens, deposits them, and repays 25 of the desired asset to settle the trade.
        solver_fill_limit_order(solver, signer::address_of(offerer), desired_fa, 25);

        assert!(primary_fungible_store::balance(signer::address_of(solver), offered_fa) == 50);
        assert!(primary_fungible_store::balance(signer::address_of(offerer), desired_fa) == 25);
        // The intent object has been consumed and removed from storage.
        assert!(!exists<PendingIntent>(signer::address_of(offerer)));
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        solver = @0xdead
    )]
    #[expected_failure(abort_code = 65537, location = fa_intent)] // error::invalid_argument(EAMOUNT_NOT_MEET)
    /// Solver fails to settle when providing fewer tokens than required.
    fun test_fa_limit_order_insufficient_solver_payment(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ) acquires PendingIntent {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let (offered_fa, _) = register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa, _) = register_and_mint_tokens(aptos_framework, solver, 100);

        let expiry_time = timestamp::now_seconds() + 3600;

        offerer_submit_limit_order(offerer, offered_fa, 50, desired_fa, 25, expiry_time);
        assert!(exists<PendingIntent>(signer::address_of(offerer)));
        // Solver attempts to complete the trade with only 10 desired tokens, triggering the amount check.
        solver_fill_limit_order(solver, signer::address_of(offerer), desired_fa, 10);
    }
}
