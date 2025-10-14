
#[test_only]
module aptos_intent::intent_reservation_tests {
    use std::signer;
    use std::vector;
    use std::option;
    use aptos_std::ed25519;
    use aptos_std::unit_test;
    use aptos_intent::fa_intent;
    use aptos_intent::intent_reservation;
    use aptos_intent::fa_test_utils::register_and_mint_tokens;

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
    /// Test: Reserved Intent Signature Verification Success
    /// Verifies that signature verification succeeds when using the correct solver key.
    fun test_fa_limit_order_reserved_intent_signature_verification_success(
        aptos_framework: &signer,
        offerer: &signer,
        desired_fa_holder: &signer,
    ) {
        // Generate Ed25519 keys for the solver
        let (solver_secret_key, _solver_public_key) = ed25519::generate_keys();
        
        // Create a solver signer for testing (for minting tokens)
        let solver_signers = unit_test::create_signers_for_testing(1);
        let solver_signer = vector::pop_back(&mut solver_signers);
        let solver_address = signer::address_of(&solver_signer);
        
        let (offered_fa_type, _offered_mint_ref) = register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _desired_mint_ref) = register_and_mint_tokens(aptos_framework, desired_fa_holder, 0);
        
        // Step 1: Offerer creates draft intent (without solver)
        let draft_intent = intent_reservation::create_draft_intent(
            offered_fa_type,
            SOURCE_AMOUNT,
            desired_fa_type,
            DESIRED_AMOUNT,
            EXPIRY_TIME,
            signer::address_of(offerer),
        );
        
        // Step 2: Solver adds their address to the draft intent
        let intent_to_sign = intent_reservation::add_solver_to_draft_intent(
            draft_intent,
            solver_address,
        );
        
        // Step 3: Hash the intent to sign
        let intent_data = intent_reservation::hash_intent(
            intent_to_sign,
        );
        
        // Sign with the generated key
        let signature = ed25519::sign_arbitrary_bytes(&solver_secret_key, intent_data);
        
        // Step 3: Test with solver address and valid signature
        fa_intent::create_fa_to_fa_intent_entry(
            offerer,
            offered_fa_type,
            SOURCE_AMOUNT,
            desired_fa_type,
            DESIRED_AMOUNT,
            EXPIRY_TIME,
            solver_address, // Use solver address
            ed25519::signature_to_bytes(&signature), // Use generated signature
        );

        // Verify the intent was created successfully
        // Note: The function should complete without aborting, indicating successful creation
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        solver = @0xdead
    )]
    #[expected_failure(abort_code = 65538, location = fa_intent)] // error::invalid_argument(EINVALID_SIGNATURE)
    /// Test: Invalid Signature Rejection
    /// Verifies that invalid signatures cause intent creation to fail.
    /// Tests that signature verification failures are properly handled.
    fun test_fa_limit_order_invalid_signature_rejection(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ) {
        let (offered_fa_type, _offered_mint_ref) = register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _desired_mint_ref) = register_and_mint_tokens(aptos_framework, solver, 0);

        // Create a reserved intent with solver authorization
        let incorrect_signature = b"incorrect_signature_for_testing";
        fa_intent::create_fa_to_fa_intent_entry(
            offerer,
            offered_fa_type,
            SOURCE_AMOUNT,
            desired_fa_type,
            DESIRED_AMOUNT,
            EXPIRY_TIME,
            signer::address_of(solver),
            incorrect_signature,
        );
    }

}
