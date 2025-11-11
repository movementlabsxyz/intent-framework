#[test_only]
module mvmt_intent::fa_intent_with_oracle_tests {
    use std::bcs;
    use std::option;
    use std::signer;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::Object;
    use aptos_framework::timestamp;
    use aptos_framework::primary_fungible_store;
    use mvmt_intent::intent::TradeSession;
    use mvmt_intent::fa_intent_with_oracle;
    use mvmt_intent::fa_test_utils::register_and_mint_tokens;
    use aptos_std::ed25519;


    const OFFER_AMOUNT: u64 = 50;
    const DESIRED_AMOUNT: u64 = 25;
    const MIN_REPORTED_VALUE: u64 = 15;
    const ORACLE_VALUE: u64 = 20;

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        solver = @0xdead
    )]
    /// Oracle-guarded limit order settles only when supplied with a valid signature witness.
    fun test_fa_limit_order_with_oracle_signature(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ) {
        let (oracle_secret_key, session, desired_fa_type, offered_fa_type) = setup_oracle_limit_order(
            aptos_framework,
            offerer,
            solver,
        );

        // Oracle signs an arbitrary reported value (20 >= minimum threshold 15).
        let signature = ed25519::sign_arbitrary_bytes(&oracle_secret_key, bcs::to_bytes(&ORACLE_VALUE));
        let witness = fa_intent_with_oracle::new_oracle_signature_witness(ORACLE_VALUE, signature);

        // Solver supplies the witness along with the desired tokens to settle the trade.
        let desired_fa = primary_fungible_store::withdraw(solver, desired_fa_type, DESIRED_AMOUNT);
        fa_intent_with_oracle::finish_fa_receiving_session_with_oracle(
            session,
            desired_fa,
            option::some(witness),
        );

        // Offerer receives the desired asset; solver receives the unlocked supply.
        assert!(primary_fungible_store::balance(signer::address_of(offerer), offered_fa_type) == OFFER_AMOUNT);
        assert!(primary_fungible_store::balance(signer::address_of(offerer), desired_fa_type) == DESIRED_AMOUNT);
        assert!(primary_fungible_store::balance(signer::address_of(solver), offered_fa_type) == OFFER_AMOUNT);
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        solver = @0xdead
    )]
    #[expected_failure(abort_code = 65538, location = fa_intent_with_oracle)] // error::invalid_argument(ESIGNATURE_REQUIRED)
    /// Settlement fails when solver omits the oracle witness entirely.
    fun test_fa_limit_order_missing_oracle_signature(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ) {
        // Setup the same intent configuration as the happy-path test.
        let (_, session, desired_fa_type, _) = setup_oracle_limit_order(aptos_framework, offerer, solver);

        // Solver tries to settle without providing a signature witness which should abort.
        let desired_fa = primary_fungible_store::withdraw(solver, desired_fa_type, DESIRED_AMOUNT);
        fa_intent_with_oracle::finish_fa_receiving_session_with_oracle(
            session,
            desired_fa,
            option::none(),
        );
    }

    #[test(
        aptos_framework = @0x1,
        offerer = @0xcafe,
        solver = @0xdead
    )]
    #[expected_failure(abort_code = 65539, location = fa_intent_with_oracle)] // error::invalid_argument(EINVALID_SIGNATURE)
    /// Settlement fails when solver supplies a signature that does not verify under the configured oracle key.
    fun test_fa_limit_order_with_invalid_oracle_signature(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ) {
        // Setup the same intent configuration as the happy-path test.
        let (_, session, desired_fa_type, _) = setup_oracle_limit_order(aptos_framework, offerer, solver);

        // Forge a signature using a different key pair so verification fails.
        let (forged_secret_key, _) = ed25519::generate_keys();
        let forged_signature = ed25519::sign_arbitrary_bytes(&forged_secret_key, bcs::to_bytes(&ORACLE_VALUE));
        let forged_witness = fa_intent_with_oracle::new_oracle_signature_witness(ORACLE_VALUE, forged_signature);

        // Solver provides the forged witness, triggering signature verification failure.
        let desired_fa = primary_fungible_store::withdraw(solver, desired_fa_type, DESIRED_AMOUNT);
        fa_intent_with_oracle::finish_fa_receiving_session_with_oracle(
            session,
            desired_fa,
            option::some(forged_witness),
        );
    }

    // ============================================================================
    // HELPERS
    // ============================================================================

    fun setup_oracle_limit_order(
        aptos_framework: &signer,
        offerer: &signer,
        solver: &signer,
    ): (
        ed25519::SecretKey,
        TradeSession<fa_intent_with_oracle::OracleGuardedLimitOrder>,
        Object<Metadata>,
        Object<Metadata>,
    ) {
        let (offered_fa_type, _) = register_and_mint_tokens(aptos_framework, offerer, 100);
        let (desired_fa_type, _) = register_and_mint_tokens(aptos_framework, solver, 100);

        let (oracle_secret_key, validated_pk) = ed25519::generate_keys();
        let oracle_public_key = ed25519::public_key_to_unvalidated(&validated_pk);
        let requirement = fa_intent_with_oracle::new_oracle_signature_requirement(
            MIN_REPORTED_VALUE,
            oracle_public_key,
        );

        let intent = fa_intent_with_oracle::create_fa_to_fa_intent_with_oracle_requirement(
            primary_fungible_store::withdraw(offerer, offered_fa_type, OFFER_AMOUNT),
            desired_fa_type,
            DESIRED_AMOUNT,
            timestamp::now_seconds() + 3600,
            signer::address_of(offerer),
            requirement,
            true, // revocable by default for tests
            @0x1, // dummy intent_id for testing
            std::option::none(), // unreserved intent
        );

        let (unlocked_fa, session) = fa_intent_with_oracle::start_fa_offering_session(solver, intent);
        primary_fungible_store::deposit(signer::address_of(solver), unlocked_fa);

        (oracle_secret_key, session, desired_fa_type, offered_fa_type)
    }
}
