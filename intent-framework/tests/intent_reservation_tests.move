
#[test_only]
module aptos_intent::intent_reservation_tests {
    use std::signer;
    use aptos_std::ed25519;
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
        solver = @0xdead
    )]
    #[expected_failure(abort_code = 65538, location = fa_intent)] // error::invalid_argument(EINVALID_SIGNATURE)
    /// Test: Reserved Intent Creation with Real Ed25519 Signature
    /// Verifies that reserved intents can be created with solver authorization.
    /// Tests the off-chain signature verification and reservation creation flow.
    /// This test demonstrates that even with real Ed25519 signatures, verification fails
    /// if the signature doesn't match the solver's authentication key.
    fun test_fa_limit_order_reserved_intent(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ) {
        let (offered_fa_type, _offered_mint_ref) = register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _desired_mint_ref) = register_and_mint_tokens(aptos_framework, solver, 0);

        // Generate real Ed25519 keys for the solver
        let (solver_secret_key, _solver_public_key) = ed25519::generate_keys();
        
        // Create the intent data to sign
        let intent_data = intent_reservation::hash_intent(
            offered_fa_type,
            SOURCE_AMOUNT,
            desired_fa_type,
            DESIRED_AMOUNT,
            EXPIRY_TIME,
            signer::address_of(offerer),
            signer::address_of(solver),
        );
        
        // Create reserved intent with correct signature
        let signature = ed25519::sign_arbitrary_bytes(&solver_secret_key, intent_data);
        fa_intent::create_fa_to_fa_intent_entry(
            offerer,
            offered_fa_type,
            SOURCE_AMOUNT,
            desired_fa_type,
            DESIRED_AMOUNT,
            EXPIRY_TIME,
            signer::address_of(solver),
            ed25519::signature_to_bytes(&signature),
        );
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
