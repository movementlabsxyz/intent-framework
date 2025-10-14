
#[test_only]
module aptos_intent::intent_reservation_tests {
    use std::signer;
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
    /// Test: Reserved Intent Creation with Dummy Signature
    /// Verifies that reserved intents can be created with solver authorization.
    /// Tests the off-chain signature verification and reservation creation flow.
    fun test_fa_limit_order_reserved_intent(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ) {
        let (offered_fa_type, _offered_mint_ref) = register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _desired_mint_ref) = register_and_mint_tokens(aptos_framework, solver, 0);

        // Solver signs the intent data off-chain
        let _msg_to_sign = intent_reservation::hash_intent(
            offered_fa_type,
            SOURCE_AMOUNT,
            desired_fa_type,
            DESIRED_AMOUNT,
            EXPIRY_TIME,
            signer::address_of(offerer),
            signer::address_of(solver),
        );

        // For now, create a dummy signature (in a real test, you'd generate proper keys)
        let dummy_signature = b"dummy_signature_for_testing";

        // Offerer creates the reserved intent on-chain
        fa_intent::create_fa_to_fa_intent_entry(
            offerer,
            offered_fa_type,
            SOURCE_AMOUNT,
            desired_fa_type,
            DESIRED_AMOUNT,
            EXPIRY_TIME,
            signer::address_of(solver),
            dummy_signature,
        );

        // TODO: Add assertions to verify the intent state
        // TODO: Test with real Ed25519 signatures for proper verification
        // TODO: Test unauthorized solver rejection
    }

}
