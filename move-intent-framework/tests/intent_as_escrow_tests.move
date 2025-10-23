#[test_only]
module aptos_intent::intent_as_escrow_tests {
    use std::signer;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_intent::intent_as_escrow;
    use aptos_intent::fa_test_utils::register_and_mint_tokens;
    use aptos_std::ed25519;

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(
        aptos_framework = @0x1,
        user = @0xcafe,
        solver = @0xdead,
        _verifier = @0xbeef
    )]
    /// Test successful escrow with verifier approval
    fun test_escrow_with_verifier_approval(
        aptos_framework: &signer,
        user: &signer,
        solver: &signer,
        _verifier: &signer,
    ) {
        // Register and mint tokens for user and solver (same token type for escrow)
        let (source_token_type, _) = register_and_mint_tokens(aptos_framework, user, 100);
        let (_desired_token_type, _) = register_and_mint_tokens(aptos_framework, solver, 100);
        
        // Give solver some of the source token type for payment
        let solver_payment_tokens = primary_fungible_store::withdraw(user, source_token_type, 50);
        primary_fungible_store::deposit(signer::address_of(solver), solver_payment_tokens);

        // Generate verifier key pair
        let (verifier_secret_key, validated_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_pk);
        
        // User creates escrow
        let source_asset = primary_fungible_store::withdraw(user, source_token_type, 50);
        let escrow_intent = intent_as_escrow::create_escrow(
            user,
            source_asset,
            verifier_public_key,
            timestamp::now_seconds() + 3600, // 1 hour expiry
        );
        
        // Solver starts escrow session
        let (escrowed_asset, session) = intent_as_escrow::start_escrow_session(escrow_intent);
        primary_fungible_store::deposit(signer::address_of(solver), escrowed_asset);
        
        // Verifier approves the escrow
        let (approval_value, verifier_signature) = intent_as_escrow::create_oracle_approval(
            &verifier_secret_key,
            true, // approve
        );

        // Solver provides payment (source token type)
        let solver_payment = primary_fungible_store::withdraw(solver, source_token_type, 50);
        intent_as_escrow::complete_escrow(
            session,
            solver_payment,
            approval_value,
            verifier_signature,
        );
        
        // User should have received payment tokens
        assert!(primary_fungible_store::balance(signer::address_of(user), source_token_type) == 50);
        
        // Solver should have received escrowed tokens
        assert!(primary_fungible_store::balance(signer::address_of(solver), source_token_type) == 50);
    }

    #[test(
        aptos_framework = @0x1,
        user = @0xcafe,
        solver = @0xdead,
        _verifier = @0xbeef
    )]
    #[expected_failure(abort_code = 65536, location = intent_as_escrow)] // ORACLE_REJECT
    /// Test escrow rejection by verifier
    fun test_escrow_with_verifier_rejection(
        aptos_framework: &signer,
        user: &signer,
        solver: &signer,
        _verifier: &signer,
    ) {
        let (source_token_type, _) = register_and_mint_tokens(aptos_framework, user, 100);
        let (_desired_token_type, _) = register_and_mint_tokens(aptos_framework, solver, 100);

        // Give solver some of the source token type for payment
        let solver_payment_tokens = primary_fungible_store::withdraw(user, source_token_type, 50);
        primary_fungible_store::deposit(signer::address_of(solver), solver_payment_tokens);

        let (verifier_secret_key, validated_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_pk);
        
        let source_asset = primary_fungible_store::withdraw(user, source_token_type, 50);
        let escrow_intent = intent_as_escrow::create_escrow(
            user,
            source_asset,
            verifier_public_key,
            timestamp::now_seconds() + 3600,
        );
        
        let (escrowed_asset, session) = intent_as_escrow::start_escrow_session(escrow_intent);
        primary_fungible_store::deposit(signer::address_of(solver), escrowed_asset);
        
        // Verifier rejects the escrow
        let (approval_value, verifier_signature) = intent_as_escrow::create_oracle_approval(
            &verifier_secret_key,
            false, // reject
        );

        // This should abort because oracle rejected
        let solver_payment = primary_fungible_store::withdraw(solver, source_token_type, 50);
        intent_as_escrow::complete_escrow(
            session,
            solver_payment,
            approval_value,
            verifier_signature,
        );
    }

    #[test(
        aptos_framework = @0x1,
        user = @0xcafe,
        solver = @0xdead,
        _verifier = @0xbeef
    )]
    /// Test escrow revocation by user
    fun test_escrow_revocation(
        aptos_framework: &signer,
        user: &signer,
        solver: &signer,
        _verifier: &signer,
    ) {
        let (source_token_type, _) = register_and_mint_tokens(aptos_framework, user, 100);
        let (_desired_token_type, _) = register_and_mint_tokens(aptos_framework, solver, 100);

        let (_verifier_secret_key, validated_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_pk);
        
        let source_asset = primary_fungible_store::withdraw(user, source_token_type, 50);
        let escrow_intent = intent_as_escrow::create_escrow(
            user,
            source_asset,
            verifier_public_key,
            timestamp::now_seconds() + 3600,
        );
        
        // User revokes the escrow before oracle acts
        intent_as_escrow::revoke_escrow(user, escrow_intent);
        
        // User should have their tokens back
        assert!(primary_fungible_store::balance(signer::address_of(user), source_token_type) == 100);
    }
}
