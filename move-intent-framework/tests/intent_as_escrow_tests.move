#[test_only]
module aptos_intent::intent_as_escrow_tests {
    use std::option;
    use std::signer;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::Object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_intent::intent_as_escrow;
    use aptos_intent::fa_test_utils::register_and_mint_tokens;
    use aptos_std::ed25519;

    const ESCROW_AMOUNT: u64 = 100;
    const DESIRED_AMOUNT: u64 = 50;

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(
        aptos_framework = @0x1,
        user = @0xalice,
        solver = @0xbob,
        verifier = @0xcharlie
    )]
    /// Test successful escrow with verifier approval
    fun test_escrow_with_verifier_approval(
        aptos_framework: &signer,
        user: &signer,
        solver: &signer,
        verifier: &signer,
    ) {
        // ============================================================================
        // SETUP
        // ============================================================================
        
        // Register and mint tokens for user and solver
        let (source_token_type, _) = register_and_mint_tokens(aptos_framework, user, 200);
        let (desired_token_type, _) = register_and_mint_tokens(aptos_framework, solver, 200);

        // Generate verifier key pair
        let (verifier_secret_key, validated_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_pk);

        // ============================================================================
        // CREATE ESCROW
        // ============================================================================
        
        // User creates escrow
        let source_asset = primary_fungible_store::withdraw(user, source_token_type, ESCROW_AMOUNT);
        let escrow_intent = intent_as_escrow::create_escrow(
            user,
            source_asset,
            verifier_public_key,
            timestamp::now_seconds() + 3600, // 1 hour expiry
        );

        // ============================================================================
        // SOLVER TAKES ESCROW
        // ============================================================================
        
        // Solver starts escrow session
        let (escrowed_asset, session) = intent_as_escrow::start_escrow_session(escrow_intent);
        primary_fungible_store::deposit(signer::address_of(solver), escrowed_asset);

        // ============================================================================
        // VERIFIER APPROVES
        // ============================================================================
        
        // Verifier approves the escrow
        let (approval_value, verifier_signature) = intent_as_escrow::create_oracle_approval(
            &verifier_secret_key,
            true, // approve
        );

        // Solver provides payment and verifier approval
        let solver_payment = primary_fungible_store::withdraw(solver, desired_token_type, DESIRED_AMOUNT);
        intent_as_escrow::complete_escrow(
            session,
            solver_payment,
            approval_value,
            verifier_signature,
        );

        // ============================================================================
        // VERIFY RESULTS
        // ============================================================================
        
        // User should have received desired tokens
        assert!(primary_fungible_store::balance(signer::address_of(user), desired_token_type) == DESIRED_AMOUNT);
        
        // Solver should have received escrowed tokens
        assert!(primary_fungible_store::balance(signer::address_of(solver), source_token_type) == ESCROW_AMOUNT);
    }

    #[test(
        aptos_framework = @0x1,
        user = @0xalice,
        solver = @0xbob,
        verifier = @0xcharlie
    )]
    #[expected_failure(abort_code = 0, location = intent_as_escrow)] // ORACLE_REJECT
    /// Test escrow rejection by verifier
    fun test_escrow_with_verifier_rejection(
        aptos_framework: &signer,
        user: &signer,
        solver: &signer,
        verifier: &signer,
    ) {
        // ============================================================================
        // SETUP
        // ============================================================================
        
        let (source_token_type, _) = register_and_mint_tokens(aptos_framework, user, 200);
        let (desired_token_type, _) = register_and_mint_tokens(aptos_framework, solver, 200);

        let (verifier_secret_key, validated_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_pk);

        // ============================================================================
        // CREATE ESCROW
        // ============================================================================
        
        let source_asset = primary_fungible_store::withdraw(user, source_token_type, ESCROW_AMOUNT);
        let escrow_intent = intent_as_escrow::create_escrow(
            user,
            source_asset,
            verifier_public_key,
            timestamp::now_seconds() + 3600,
        );

        // ============================================================================
        // SOLVER TAKES ESCROW
        // ============================================================================
        
        let (escrowed_asset, session) = intent_as_escrow::start_escrow_session(escrow_intent);
        primary_fungible_store::deposit(signer::address_of(solver), escrowed_asset);

        // ============================================================================
        // ORACLE REJECTS
        // ============================================================================
        
        // Verifier rejects the escrow
        let (approval_value, verifier_signature) = intent_as_escrow::create_oracle_approval(
            &verifier_secret_key,
            false, // reject
        );

        // This should abort because oracle rejected
        let solver_payment = primary_fungible_store::withdraw(solver, desired_token_type, DESIRED_AMOUNT);
        intent_as_escrow::complete_escrow(
            session,
            solver_payment,
            approval_value,
            oracle_signature,
        );
    }

    #[test(
        aptos_framework = @0x1,
        user = @0xalice,
        solver = @0xbob,
        oracle = @0xcharlie
    )]
    /// Test escrow revocation by user
    fun test_escrow_revocation(
        aptos_framework: &signer,
        user: &signer,
        solver: &signer,
        oracle: &signer,
    ) {
        // ============================================================================
        // SETUP
        // ============================================================================
        
        let (source_token_type, _) = register_and_mint_tokens(aptos_framework, user, 200);
        let (desired_token_type, _) = register_and_mint_tokens(aptos_framework, solver, 200);

        let (verifier_secret_key, validated_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_pk);

        // ============================================================================
        // CREATE ESCROW
        // ============================================================================
        
        let source_asset = primary_fungible_store::withdraw(user, source_token_type, ESCROW_AMOUNT);
        let escrow_intent = intent_as_escrow::create_escrow(
            user,
            source_asset,
            verifier_public_key,
            timestamp::now_seconds() + 3600,
        );

        // ============================================================================
        // USER REVOKES ESCROW
        // ============================================================================
        
        // User revokes the escrow before oracle acts
        intent_as_escrow::revoke_escrow(user, escrow_intent);

        // ============================================================================
        // VERIFY RESULTS
        // ============================================================================
        
        // User should have their tokens back
        assert!(primary_fungible_store::balance(signer::address_of(user), source_token_type) == 200);
    }
}
