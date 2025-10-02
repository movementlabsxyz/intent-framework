
#[test_only]
module aptos_intent::intent_reservation_tests {
    use std::signer;
    use aptos_intent::fa_intent;
    use aptos_intent::intent_reservation;
    use aptos_intent::fa_test_utils::register_and_mint_tokens;

    #[test(
        aptos_framework = @0x1,
        issuer = @0x999,
        solver = @0x888
    )]
    fun test_create_reserved_intent(
        aptos_framework: &signer,
        issuer: &signer,
        solver: &signer,
    ) {
        let solver_address = signer::address_of(solver);

        // Create dummy metadata and assets using the test utilities
        let (source_metadata_obj, _source_mint_ref) = register_and_mint_tokens(aptos_framework, issuer, 100);
        let (desired_metadata_obj, _desired_mint_ref) = register_and_mint_tokens(aptos_framework, solver, 0);

        let source_amount = 50;
        let desired_amount = 25;
        let expiry_time = 3600; // Simple expiry time for testing

        // Solver signs the intent data off-chain
        let _msg_to_sign = intent_reservation::hash_intent(
            source_metadata_obj,
            source_amount,
            desired_metadata_obj,
            desired_amount,
            expiry_time,
            signer::address_of(issuer),
            solver_address,
        );

        // For now, create a dummy signature (in a real test, you'd generate proper keys)
        let dummy_signature = b"dummy_signature_for_testing";

        // Issuer creates the reserved intent on-chain
        fa_intent::create_fa_to_fa_intent_entry(
            issuer,
            source_metadata_obj,
            source_amount,
            desired_metadata_obj,
            desired_amount,
            expiry_time,
            solver_address,
            dummy_signature,
        );

        // TODO: Add assertions to verify the intent state
    }
}
