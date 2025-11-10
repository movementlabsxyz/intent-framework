#[test_only]
module aptos_intent::intent_as_escrow_tests {
    use std::signer;
    use std::bcs;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_intent::intent_as_escrow;
    use aptos_intent::fa_intent_with_oracle;
    use aptos_intent::fa_test_utils::register_and_mint_tokens;
    use aptos_intent::intent_reservation;
    use aptos_std::ed25519;

    // ============================================================================
    // TEST HELPER FUNCTIONS
    // ============================================================================

    /// Gets the approval constants for testing
    fun get_oracle_approve(): u64 { 1 }
    /// Gets the rejection constants for testing  
    fun get_oracle_reject(): u64 { 0 }

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
        
        // User creates escrow (must specify reserved solver)
        let source_asset = primary_fungible_store::withdraw(user, source_token_type, 50);
        let reservation = intent_reservation::new_reservation(signer::address_of(solver));
        let escrow_intent = intent_as_escrow::create_escrow(
            user,
            source_asset,
            verifier_public_key,
            timestamp::now_seconds() + 3600, // 1 hour expiry
            @0x1, // dummy intent_id for testing
            reservation, // Escrow must be reserved for a specific solver
        );
        
        // Solver starts escrow session
        let (escrowed_asset, session) = intent_as_escrow::start_escrow_session(solver, escrow_intent);
        primary_fungible_store::deposit(signer::address_of(solver), escrowed_asset);
        
        // Verifier approves the escrow
        let approval_value = get_oracle_approve();
        let verifier_signature = ed25519::sign_arbitrary_bytes(&verifier_secret_key, bcs::to_bytes(&approval_value));

        // Solver provides payment (source token type)
        let solver_payment = primary_fungible_store::withdraw(solver, source_token_type, 50);
        intent_as_escrow::complete_escrow(
            solver,
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
        let reservation = intent_reservation::new_reservation(signer::address_of(solver));
        let escrow_intent = intent_as_escrow::create_escrow(
            user,
            source_asset,
            verifier_public_key,
            timestamp::now_seconds() + 3600,
            @0x1, // dummy intent_id for testing
            reservation, // Escrow must be reserved for a specific solver
        );
        
        let (escrowed_asset, session) = intent_as_escrow::start_escrow_session(solver, escrow_intent);
        primary_fungible_store::deposit(signer::address_of(solver), escrowed_asset);
        
        // Verifier rejects the escrow
        let approval_value = get_oracle_reject();
        let verifier_signature = ed25519::sign_arbitrary_bytes(&verifier_secret_key, bcs::to_bytes(&approval_value));

        // This should abort because oracle rejected
        let solver_payment = primary_fungible_store::withdraw(solver, source_token_type, 50);
        intent_as_escrow::complete_escrow(
            solver,
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
    #[expected_failure(abort_code = 327684, location = aptos_intent::intent)] // error::permission_denied(ENOT_REVOCABLE)
    /// Test that escrow intents cannot be revoked (they are non-revocable by design)
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
        let reservation = intent_reservation::new_reservation(signer::address_of(solver));
        let escrow_intent = intent_as_escrow::create_escrow(
            user,
            source_asset,
            verifier_public_key,
            timestamp::now_seconds() + 3600,
            @0x1, // dummy intent_id for testing
            reservation, // Escrow must be reserved for a specific solver
        );
        
        // User tries to revoke the escrow directly - this should fail because escrow is non-revocable
        fa_intent_with_oracle::revoke_fa_intent(user, escrow_intent);
    }

    #[test(
        aptos_framework = @0x1,
        user = @0xcafe,
        solver = @0xbeef
    )]
    /// Test the CLI-friendly wrapper function for creating escrow with any fungible asset
    fun test_create_escrow_from_fa(
        aptos_framework: &signer,
        user: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        // Create test fungible asset metadata for testing
        let (fa_metadata, _) = register_and_mint_tokens(aptos_framework, user, 100);
        
        // Generate verifier key pair
        let (_, validated_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_pk);
        
        // Convert to vector<u8> for the wrapper function
        let verifier_public_key_bytes = ed25519::unvalidated_public_key_to_bytes(&verifier_public_key);
        
        // Test the wrapper function: create escrow from FA (must specify reserved solver)
        aptos_intent::intent_as_escrow_entry::create_escrow_from_fa(
            user,
            fa_metadata,
            50,
            verifier_public_key_bytes,
            timestamp::now_seconds() + 3600,
            @0x1, // dummy intent_id for testing
            signer::address_of(solver), // Reserved solver address
        );
        
        // Verify user's balance decreased by 50
        assert!(primary_fungible_store::balance(signer::address_of(user), fa_metadata) == 50);
        
        // Verify escrow intent was created (it should exist)
        // Note: We can't easily verify the escrow intent object without more complex checks
    }
}
