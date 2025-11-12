
#[test_only]
module mvmt_intent::intent_reservation_tests {
    use std::signer;
    use std::option;
    use aptos_std::ed25519;
    use aptos_framework::timestamp;
    use mvmt_intent::fa_intent;
    use mvmt_intent::intent_reservation;
    use mvmt_intent::solver_registry;
    use mvmt_intent::test_utils;

    const SOURCE_AMOUNT: u64 = 50;
    const DESIRED_AMOUNT: u64 = 25;
    const EXPIRY_TIME: u64 = 3600;

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        desired_fa_holder = @0xefca
    )]
    /// Test: Signature Verification Success
    /// Verifies that signature verification succeeds when using the correct solver key.
    fun test_fa_limit_order_signature_verification_success(
        aptos_framework: &signer,
        offerer: &signer,
        desired_fa_holder: &signer,
    ) {
        // Generate Ed25519 keys for the solver
        let (solver_secret_key, solver_public_key) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&solver_public_key);
        let solver_unvalidated_public_key = ed25519::new_unvalidated_public_key_from_bytes(solver_public_key_bytes);
        
        // Use offerer as solver address - verification uses the provided public key, not the address
        let solver_address = signer::address_of(offerer);

        let (offered_fa_type, _offered_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _desired_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, desired_fa_holder, 0);
        
        // Step 1: Offerer creates draft intent (without solver)
        let draft_intent = intent_reservation::create_draft_intent(
            offered_fa_type, SOURCE_AMOUNT, desired_fa_type, DESIRED_AMOUNT, EXPIRY_TIME, signer::address_of(offerer)
        );
        
        // Step 2: Solver adds their address to the draft intent
        let intent_to_sign = intent_reservation::add_solver_to_draft_intent(draft_intent, solver_address);
        
        // Step 3: Hash the intent to sign and sign it
        let intent_data = intent_reservation::hash_intent(intent_to_sign);
        let signature = ed25519::sign_arbitrary_bytes(&solver_secret_key, intent_data);
        
        // Test signature verification with the generated public key
        let result = intent_reservation::verify_and_create_reservation_with_public_key(
            intent_to_sign, ed25519::signature_to_bytes(&signature), &solver_unvalidated_public_key
        );
        
        // Verify the signature verification succeeded
        assert!(option::is_some(&result), 0);
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        desired_fa_holder = @0xefca
    )]
    /// Test: Wrong Data Signature Verification Failure
    /// Verifies that signature verification fails when signing wrong data with correct key.
    fun test_fa_limit_order_wrong_data_signature_verification_failure(
        aptos_framework: &signer,
        offerer: &signer,
        desired_fa_holder: &signer,
    ) {
        // Generate Ed25519 keys for the solver
        let (solver_secret_key, solver_public_key) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&solver_public_key);
        let solver_unvalidated_public_key = ed25519::new_unvalidated_public_key_from_bytes(solver_public_key_bytes);
        
        // Use offerer as solver address - verification uses the provided public key, not the address
        let solver_address = signer::address_of(offerer);

        let (offered_fa_type, _offered_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _desired_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, desired_fa_holder, 0);
        
        // Step 1: Offerer creates draft intent (without solver)
        let draft_intent = intent_reservation::create_draft_intent(
            offered_fa_type, SOURCE_AMOUNT, desired_fa_type, DESIRED_AMOUNT, EXPIRY_TIME, signer::address_of(offerer)
        );
        
        // Step 2: Solver adds their address to the draft intent
        let intent_to_sign = intent_reservation::add_solver_to_draft_intent(draft_intent, solver_address);
        
        // Step 3: Sign with WRONG data instead of the actual intent data
        let wrong_data = b"wrong_data_for_testing";
        let signature = ed25519::sign_arbitrary_bytes(&solver_secret_key, wrong_data);
        
        // Test signature verification with the generated public key
        let result = intent_reservation::verify_and_create_reservation_with_public_key(
            intent_to_sign, ed25519::signature_to_bytes(&signature), &solver_unvalidated_public_key
        );
        
        // Verify the signature verification failed
        assert!(option::is_none(&result), 0);
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        desired_fa_holder = @0xefca
    )]
    /// Test: Wrong Signature Verification Failure
    /// Verifies that signature verification fails when using a completely wrong signature.
    fun test_fa_limit_order_wrong_signature_verification_failure(
        aptos_framework: &signer,
        offerer: &signer,
        desired_fa_holder: &signer,
    ) {
        // Generate Ed25519 keys for the solver
        let (_solver_secret_key, solver_public_key) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&solver_public_key);
        let solver_unvalidated_public_key = ed25519::new_unvalidated_public_key_from_bytes(solver_public_key_bytes);
        
        // Use offerer as solver address - verification uses the provided public key, not the address
        let solver_address = signer::address_of(offerer);

        let (offered_fa_type, _offered_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _desired_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, desired_fa_holder, 0);
        
        // Step 1: Offerer creates draft intent (without solver)
        let draft_intent = intent_reservation::create_draft_intent(
            offered_fa_type, SOURCE_AMOUNT, desired_fa_type, DESIRED_AMOUNT, EXPIRY_TIME, signer::address_of(offerer)
        );
        
        // Step 2: Solver adds their address to the draft intent
        let intent_to_sign = intent_reservation::add_solver_to_draft_intent(draft_intent, solver_address);
        
        // Step 3: Use a completely wrong signature (64 bytes of random data)
        let wrong_signature_bytes = b"1234567890123456789012345678901234567890123456789012345678901234";
        
        // Test signature verification with the generated public key
        let result = intent_reservation::verify_and_create_reservation_with_public_key(
            intent_to_sign, wrong_signature_bytes, &solver_unvalidated_public_key
        );
        
        // Verify the signature verification failed
        assert!(option::is_none(&result), 0);
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        solver = @0xdead
    )]
    #[expected_failure(abort_code = 65540, location = intent_reservation)] // error::invalid_argument(EINVALID_AUTH_KEY_FORMAT)
    /// Test: Invalid Authentication Key Format Rejection
    /// Verifies that accounts with new authentication key format (32 bytes) are rejected.
    /// Test accounts use the new format, so they fail at authentication key extraction.
    /// This tests that verify_and_create_reservation correctly rejects accounts that don't have
    /// the old 33-byte authentication key format needed to extract the Ed25519 public key.
    fun test_fa_limit_order_invalid_auth_key_format_rejection(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ) {
        let (offered_fa_type, _offered_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _desired_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, solver, 0);

        // Create a reserved intent with solver authorization
        // This will fail because test accounts use new authentication key format (32 bytes)
        // which cannot be used to extract the Ed25519 public key for signature verification
        let incorrect_signature = b"incorrect_signature_for_testing";
        fa_intent::create_fa_to_fa_intent_entry(
            offerer, offered_fa_type, SOURCE_AMOUNT, desired_fa_type, DESIRED_AMOUNT, 
            EXPIRY_TIME, signer::address_of(solver), incorrect_signature
        );
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        desired_fa_holder = @0xefca
    )]
    /// Test: Invalid Signature Rejection with Public Key
    /// Verifies that signature verification fails when using an invalid signature with a valid public key.
    /// This tests the signature verification logic when the public key is provided explicitly
    /// (as required for new authentication key format accounts).
    fun test_fa_limit_order_invalid_signature_rejection(
        aptos_framework: &signer,
        offerer: &signer,
        desired_fa_holder: &signer,
    ) {
        // Generate Ed25519 keys for the solver
        let (_solver_secret_key, solver_public_key) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&solver_public_key);
        let solver_unvalidated_public_key = ed25519::new_unvalidated_public_key_from_bytes(solver_public_key_bytes);
        
        // Use offerer as solver address
        let solver_address = signer::address_of(offerer);

        let (offered_fa_type, _offered_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _desired_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, desired_fa_holder, 0);
        
        // Step 1: Offerer creates draft intent (without solver)
        let draft_intent = intent_reservation::create_draft_intent(
            offered_fa_type, SOURCE_AMOUNT, desired_fa_type, DESIRED_AMOUNT, EXPIRY_TIME, signer::address_of(offerer)
        );
        
        // Step 2: Solver adds their address to the draft intent
        let intent_to_sign = intent_reservation::add_solver_to_draft_intent(draft_intent, solver_address);
        
        // Step 3: Use an invalid signature (64 bytes of random data, not a valid signature)
        let invalid_signature_bytes = b"1234567890123456789012345678901234567890123456789012345678901234";
        
        // Test signature verification with the generated public key
        // This should fail because the signature is invalid
        let result = intent_reservation::verify_and_create_reservation_with_public_key(
            intent_to_sign, invalid_signature_bytes, &solver_unvalidated_public_key
        );
        
        // Verify the signature verification failed
        assert!(option::is_none(&result), 0);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        offerer = @0xcafe,
        solver = @0xdead,
        desired_fa_holder = @0xefca
    )]
    /// Test: Signature Verification Using Solver Registry
    /// Demonstrates how to use verify_and_create_reservation_from_registry.
    /// The solver registers their public key in the registry, then when the offerer
    /// submits a transaction with the solver's signature, the contract verifies
    /// the signature on-chain by looking up the public key from the registry.
    fun test_verify_reservation_from_registry(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        offerer: &signer,
        solver: &signer,
        desired_fa_holder: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Step 1: Initialize solver registry
        solver_registry::init_for_test(mvmt_intent);
        
        // Step 2: Solver generates keys and registers in the registry
        let (solver_secret_key, solver_public_key) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&solver_public_key);
        
        // Create EVM address for solver (required for registration)
        let evm_address = test_utils::create_test_evm_address(0);
        
        // Register solver in the registry
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_address);
        assert!(solver_registry::is_registered(signer::address_of(solver)), 0);
        
        // Step 3: Offerer creates draft intent (without solver)
        let (offered_fa_type, _offered_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _desired_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, desired_fa_holder, 0);
        
        let draft_intent = intent_reservation::create_draft_intent(
            offered_fa_type, SOURCE_AMOUNT, desired_fa_type, DESIRED_AMOUNT, EXPIRY_TIME, signer::address_of(offerer)
        );
        
        // Step 4: Solver adds their address to the draft intent and signs it
        let solver_address = signer::address_of(solver);
        let intent_to_sign = intent_reservation::add_solver_to_draft_intent(draft_intent, solver_address);
        
        // Step 5: Solver signs the intent
        let intent_data = intent_reservation::hash_intent(intent_to_sign);
        let signature = ed25519::sign_arbitrary_bytes(&solver_secret_key, intent_data);
        let signature_bytes = ed25519::signature_to_bytes(&signature);
        
        // Step 6: Offerer verifies the signature using the solver registry
        // This function looks up the solver's public key from the registry automatically
        let result = intent_reservation::verify_and_create_reservation_from_registry(
            intent_to_sign,
            signature_bytes,
        );
        
        // Verify the signature verification succeeded
        assert!(option::is_some(&result), 1);
        
        // Verify the reservation contains the correct solver address
        let reservation = option::borrow(&result);
        assert!(intent_reservation::solver(reservation) == solver_address, 2);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        offerer = @0xcafe,
        solver = @0xdead,
        desired_fa_holder = @0xefca
    )]
    #[expected_failure(abort_code = 65542, location = intent_reservation)] // error::invalid_argument(ESOLVER_NOT_REGISTERED)
    /// Test: Verification Fails When Solver Not Registered
    /// Verifies that verify_and_create_reservation_from_registry fails when
    /// the solver is not registered in the solver registry.
    fun test_verify_reservation_from_registry_unregistered_solver(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        offerer: &signer,
        solver: &signer,
        desired_fa_holder: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Initialize solver registry but don't register the solver
        solver_registry::init_for_test(mvmt_intent);
        
        // Generate keys for solver (but don't register)
        let (solver_secret_key, _solver_public_key) = ed25519::generate_keys();
        
        // Create draft intent
        let (offered_fa_type, _offered_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _desired_mint_ref) = test_utils::register_and_mint_tokens(aptos_framework, desired_fa_holder, 0);
        
        let draft_intent = intent_reservation::create_draft_intent(
            offered_fa_type, SOURCE_AMOUNT, desired_fa_type, DESIRED_AMOUNT, EXPIRY_TIME, signer::address_of(offerer)
        );
        
        let solver_address = signer::address_of(solver);
        let intent_to_sign = intent_reservation::add_solver_to_draft_intent(draft_intent, solver_address);
        
        // Sign the intent
        let intent_data = intent_reservation::hash_intent(intent_to_sign);
        let signature = ed25519::sign_arbitrary_bytes(&solver_secret_key, intent_data);
        let signature_bytes = ed25519::signature_to_bytes(&signature);
        
        // This should abort because solver is not registered
        intent_reservation::verify_and_create_reservation_from_registry(
            intent_to_sign,
            signature_bytes,
        );
    }

}
