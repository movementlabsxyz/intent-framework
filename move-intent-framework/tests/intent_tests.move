#[test_only]
module mvmt_intent::intent_tests {
    use std::signer;
    use std::option;
    use aptos_framework::timestamp;
    use aptos_framework::object;
    use mvmt_intent::intent;

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    #[test_only]
    struct TestResource has store, drop {
        value: u64,
    }

    #[test_only]
    struct TestArgs has store, drop {
        condition: u64, // Arbitrary test condition (e.g., price threshold, minimum amount)
    }

    #[test_only]
    struct TestWitness has drop {}


    #[test_only]
    /// Helper function to create a test intent with standard test data.
    /// Sets up timestamp system and creates an intent with TestResource and TestArgs.
    fun create_test_intent(
        aptos_framework: &signer,
        offerer: &signer,
    ): object::Object<intent::TradeIntent<TestResource, TestArgs>> {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let resource = TestResource { value: 100 };
        let args = TestArgs { condition: 1111 };
        let expiry_time = timestamp::now_seconds() + 3600;

        intent::create_intent(
            resource,
            args,
            expiry_time,
            signer::address_of(offerer),
            TestWitness {},
            option::none(),
            true, // revocable by default for tests
        )
    }

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(
        aptos_framework = @0x1,
        offerer = @0x123
    )]
    /// Test: Complete Intent Session
    /// Tests the full lifecycle from intent creation to completion with witness validation.
    fun test_start_and_finish_intent_session(
        aptos_framework: &signer,
        offerer: &signer,
    ) {
        let intent = create_test_intent(aptos_framework, offerer);
        
        // Verify intent was created
        assert!(object::object_address(&intent) != @0x0);
        
        // Start the session
        let (unlocked_resource, session) = intent::start_intent_session(intent);
        assert!(unlocked_resource.value == 100);
        
        // Verify we can get the argument
        let retrieved_args = intent::get_argument(&session);
        assert!(retrieved_args.condition == 1111);
        
        // Finish the session (aborts if witness type is invalid)
        intent::finish_intent_session(session, TestWitness {});
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0x123
    )]
    fun test_revoke_intent_success(
        aptos_framework: &signer,
        offerer: &signer,
    ) {
        let intent = create_test_intent(aptos_framework, offerer);

        // Revoke the intent (returns the locked resource to the owner)
        let returned_resource = intent::revoke_intent(offerer, intent);
        assert!(returned_resource.value == 100);
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0x123
    )]
    #[expected_failure(abort_code = 327684, location = mvmt_intent::intent)] // error::permission_denied(ENOT_REVOCABLE)
    fun test_revoke_intent_failure(
        aptos_framework: &signer,
        offerer: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        let resource = TestResource { value: 100 };
        let args = TestArgs { condition: 1111 };
        let expiry_time = timestamp::now_seconds() + 3600;

        let intent = intent::create_intent(
            resource,
            args,
            expiry_time,
            signer::address_of(offerer),
            TestWitness {},
            option::none(),
            false, // revocable = false
        );

        // This should fail because the intent is not revocable
        let returned_resource = intent::revoke_intent(offerer, intent);
        assert!(returned_resource.value == 100);
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0x123
    )]
    #[expected_failure(abort_code = 327680, location = intent)] // error::permission_denied(EINTENT_EXPIRED)
    /// Test: Expired Intent Protection
    /// Verifies that expired intents cannot be executed and fail with proper error.
    fun test_expired_intent_cannot_start_session(
        aptos_framework: &signer,
        offerer: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        let resource = TestResource { value: 100 };
        let args = TestArgs { condition: 1111 };
        let expiry_time = 1; // Set to 1 second
        
        let intent = intent::create_intent(
            resource,
            args,
            expiry_time,
            signer::address_of(offerer),
            TestWitness {},
            option::none(),
            true, // revocable by default for tests
        );
        
        // Advance time to make the intent expired
        timestamp::fast_forward_seconds(2);
        
        // This should fail because the intent is expired
        // We need to handle the return values even though the function should abort
        let (_resource, session) = intent::start_intent_session(intent);
        // If we get here, the test failed - we should finish the session
        intent::finish_intent_session(session, TestWitness {});
    }
}
