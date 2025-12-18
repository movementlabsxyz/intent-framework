#[test_only]
module mvmt_intent::intent_registry_tests {
    use std::signer;
    use std::vector;

    use aptos_framework::timestamp;
    use mvmt_intent::intent_registry;

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123
    )]
    /// What is tested: initialize creates an empty registry
    /// Why: Ensure the registry starts clean with no active requesters
    fun test_initialize_registry(
        aptos_framework: &signer,
        mvmt_intent: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        intent_registry::init_for_test(mvmt_intent);

        let active = intent_registry::get_active_requesters();
        assert!(vector::length(&active) == 0, 0);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requester = @0xcafe
    )]
    /// What is tested: register_intent adds intent and unregister_intent removes it
    /// Why: Ensure intent lifecycle is tracked accurately for verifier polling
    fun test_register_unregister_lifecycle(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requester: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        intent_registry::init_for_test(mvmt_intent);

        let addr = signer::address_of(requester);
        let intent_id_1 = @0x1111;
        let intent_id_2 = @0x2222;
        let expiry = timestamp::now_seconds() + 3600;

        // Register first intent -> requester appears
        intent_registry::register_intent_for_test(addr, intent_id_1, expiry);
        let active1 = intent_registry::get_active_requesters();
        assert!(vector::length(&active1) == 1, 0);
        assert!(vector::contains(&active1, &addr), 1);
        assert!(intent_registry::get_intent_count(addr) == 1, 2);

        // Register second intent -> still one requester, but count is 2
        intent_registry::register_intent_for_test(addr, intent_id_2, expiry);
        let active2 = intent_registry::get_active_requesters();
        assert!(vector::length(&active2) == 1, 3);
        assert!(intent_registry::get_intent_count(addr) == 2, 4);

        // Unregister first intent -> requester still present (1 intent left)
        intent_registry::unregister_intent_for_test(intent_id_1);
        let active3 = intent_registry::get_active_requesters();
        assert!(vector::length(&active3) == 1, 5);
        assert!(intent_registry::get_intent_count(addr) == 1, 6);

        // Unregister second intent -> requester removed
        intent_registry::unregister_intent_for_test(intent_id_2);
        let active4 = intent_registry::get_active_requesters();
        assert!(vector::length(&active4) == 0, 7);
        assert!(intent_registry::get_intent_count(addr) == 0, 8);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requester = @0xcafe,
        cleaner = @0xbeef
    )]
    /// What is tested: cleanup_expired only works for truly expired intents
    /// Why: Prevent malicious actors from removing active intents
    fun test_cleanup_expired_only_after_expiry(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requester: &signer,
        cleaner: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        intent_registry::init_for_test(mvmt_intent);

        let addr = signer::address_of(requester);
        let intent_id = @0x1111;
        let expiry = timestamp::now_seconds() + 10; // expires in 10 seconds

        // Register intent
        intent_registry::register_intent_for_test(addr, intent_id, expiry);
        assert!(intent_registry::is_intent_registered(intent_id), 0);
        assert!(intent_registry::get_intent_count(addr) == 1, 1);

        // Fast forward past expiry
        timestamp::fast_forward_seconds(11);

        // Now cleanup_expired should succeed
        intent_registry::cleanup_expired(cleaner, intent_id);
        assert!(!intent_registry::is_intent_registered(intent_id), 2);
        assert!(intent_registry::get_intent_count(addr) == 0, 3);

        let active = intent_registry::get_active_requesters();
        assert!(vector::length(&active) == 0, 4);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requester = @0xcafe,
        cleaner = @0xbeef
    )]
    #[expected_failure(abort_code = 327684, location = intent_registry)] // E_INTENT_NOT_EXPIRED
    /// What is tested: cleanup_expired fails if intent is not expired
    /// Why: Prevent malicious removal of active intents
    fun test_cleanup_expired_fails_if_not_expired(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requester: &signer,
        cleaner: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        intent_registry::init_for_test(mvmt_intent);

        let addr = signer::address_of(requester);
        let intent_id = @0x1111;
        let expiry = timestamp::now_seconds() + 3600; // expires in 1 hour

        // Register intent
        intent_registry::register_intent_for_test(addr, intent_id, expiry);

        // Try to cleanup before expiry - should fail
        intent_registry::cleanup_expired(cleaner, intent_id);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        cleaner = @0xbeef
    )]
    #[expected_failure(abort_code = 393219, location = intent_registry)] // E_INTENT_NOT_FOUND
    /// What is tested: cleanup_expired fails for non-existent intent
    /// Why: Prevent cleanup of intents that were never registered or already cleaned
    fun test_cleanup_expired_fails_if_not_found(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        cleaner: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        intent_registry::init_for_test(mvmt_intent);

        let fake_intent_id = @0x9999;

        // Try to cleanup non-existent intent - should fail
        intent_registry::cleanup_expired(cleaner, fake_intent_id);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123
    )]
    /// What is tested: unregister_intent is idempotent for non-existent intents
    /// Why: Fulfillment code can safely call unregister even if intent was already cleaned up
    fun test_unregister_idempotent(
        aptos_framework: &signer,
        mvmt_intent: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        intent_registry::init_for_test(mvmt_intent);

        let fake_intent_id = @0x9999;

        // Should not fail - just silently returns
        intent_registry::unregister_intent_for_test(fake_intent_id);

        let active = intent_registry::get_active_requesters();
        assert!(vector::length(&active) == 0, 0);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requester1 = @0xcafe,
        requester2 = @0xbeef
    )]
    /// What is tested: multiple requesters are tracked independently
    /// Why: Ensure each requester's intents are isolated
    fun test_multiple_requesters(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requester1: &signer,
        requester2: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        intent_registry::init_for_test(mvmt_intent);

        let addr1 = signer::address_of(requester1);
        let addr2 = signer::address_of(requester2);
        let intent_id_1 = @0x1111;
        let intent_id_2 = @0x2222;
        let expiry = timestamp::now_seconds() + 3600;

        // Register intent for requester1
        intent_registry::register_intent_for_test(addr1, intent_id_1, expiry);
        
        // Register intent for requester2
        intent_registry::register_intent_for_test(addr2, intent_id_2, expiry);

        // Both should be active
        let active = intent_registry::get_active_requesters();
        assert!(vector::length(&active) == 2, 0);
        assert!(intent_registry::get_intent_count(addr1) == 1, 1);
        assert!(intent_registry::get_intent_count(addr2) == 1, 2);

        // Unregister requester1's intent
        intent_registry::unregister_intent_for_test(intent_id_1);

        // Only requester2 should remain
        let active2 = intent_registry::get_active_requesters();
        assert!(vector::length(&active2) == 1, 3);
        assert!(vector::contains(&active2, &addr2), 4);
        assert!(intent_registry::get_intent_count(addr1) == 0, 5);
        assert!(intent_registry::get_intent_count(addr2) == 1, 6);
    }
}
