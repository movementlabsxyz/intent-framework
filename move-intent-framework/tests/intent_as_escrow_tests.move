#[test_only]
module mvmt_intent::intent_as_escrow_tests {
    use std::signer;
    use std::bcs;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use mvmt_intent::intent_as_escrow;
    use mvmt_intent::fa_intent_with_oracle;
    use mvmt_intent::test_utils;
    use mvmt_intent::intent_reservation;
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
    /// What is tested: complete_escrow succeeds when the verifier signature and payment are valid
    /// Why: Ensure the happy-path escrow flow correctly settles between requester and solver
    fun test_escrow_with_verifier_approval(
        aptos_framework: &signer,
        user: &signer,
        solver: &signer,
        _verifier: &signer,
    ) {
        // Register and mint tokens for requester and solver (same token type for escrow)
        let (offered_token_type, _) = test_utils::register_and_mint_tokens(aptos_framework, user, 100);
        let (_desired_token_type, _) = test_utils::register_and_mint_tokens(aptos_framework, solver, 100);
        
        // Give solver some of the source token type for payment
        let solver_payment_tokens = primary_fungible_store::withdraw(user, offered_token_type, 50);
        primary_fungible_store::deposit(signer::address_of(solver), solver_payment_tokens);

        // Generate verifier key pair
        let (verifier_secret_key, validated_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_pk);
        
        // Requester creates escrow (must specify reserved solver)
        let offered_asset = primary_fungible_store::withdraw(user, offered_token_type, 50);
        let reservation = intent_reservation::new_reservation(signer::address_of(solver));
        let escrow_intent = intent_as_escrow::create_escrow(
            user,
            offered_asset,
            2, // offered_chain_id: connected chain where escrow is created
            verifier_public_key,
            timestamp::now_seconds() + 3600, // 1 hour expiry
            @0x1, // dummy intent_id for testing
            reservation, // Escrow must be reserved for a specific solver
            1, // desired_chain_id: hub chain where tokens are desired
        );
        
        // Solver starts escrow session
        let (escrowed_asset, session) = intent_as_escrow::start_escrow_session(solver, escrow_intent);
        primary_fungible_store::deposit(signer::address_of(solver), escrowed_asset);
        
        // Verifier signs the intent_id - the signature itself is the approval
        let intent_id = @0x1; // Same intent_id used when creating escrow
        let verifier_signature = ed25519::sign_arbitrary_bytes(&verifier_secret_key, bcs::to_bytes(&intent_id));

        // Solver provides payment (source token type)
        let solver_payment = primary_fungible_store::withdraw(solver, offered_token_type, 50);
        intent_as_escrow::complete_escrow(
            solver,
            session,
            solver_payment,
            verifier_signature,
        );
        
        // Requester should have received payment tokens
        assert!(primary_fungible_store::balance(signer::address_of(user), offered_token_type) == 50);
        
        // Solver should have received escrowed tokens
        assert!(primary_fungible_store::balance(signer::address_of(solver), offered_token_type) == 50);
    }

    #[test(
        aptos_framework = @0x1,
        user = @0xcafe,
        solver = @0xdead,
        _verifier = @0xbeef
    )]
    #[expected_failure(abort_code = 65539, location = fa_intent_with_oracle)] // error::invalid_argument(EINVALID_SIGNATURE)
    /// What is tested: escrow completion fails when the verifier signs the wrong intent_id
    /// Why: Prevent misuse of approvals by binding signatures to a specific escrow intent_id
    fun test_escrow_with_wrong_intent_id_signature(
        aptos_framework: &signer,
        user: &signer,
        solver: &signer,
        _verifier: &signer,
    ) {
        let (offered_token_type, _) = test_utils::register_and_mint_tokens(aptos_framework, user, 100);
        let (_desired_token_type, _) = test_utils::register_and_mint_tokens(aptos_framework, solver, 100);

        // Give solver some of the source token type for payment
        let solver_payment_tokens = primary_fungible_store::withdraw(user, offered_token_type, 50);
        primary_fungible_store::deposit(signer::address_of(solver), solver_payment_tokens);

        let (verifier_secret_key, validated_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_pk);
        
        // Create escrow with intent_id = @0x1
        let offered_asset = primary_fungible_store::withdraw(user, offered_token_type, 50);
        let reservation = intent_reservation::new_reservation(signer::address_of(solver));
        let escrow_intent = intent_as_escrow::create_escrow(
            user,
            offered_asset,
            2, // offered_chain_id: connected chain where escrow is created
            verifier_public_key,
            timestamp::now_seconds() + 3600,
            @0x1, // Escrow created with intent_id = @0x1
            reservation,
            1, // desired_chain_id: hub chain where tokens are desired
        );
        
        let (escrowed_asset, session) = intent_as_escrow::start_escrow_session(solver, escrow_intent);
        primary_fungible_store::deposit(signer::address_of(solver), escrowed_asset);
        
        // Verifier signs a DIFFERENT intent_id (@0x2) instead of the escrow's intent_id (@0x1)
        // This should cause signature verification to fail
        let wrong_intent_id = @0x2; // Different from escrow's intent_id (@0x1)
        let verifier_signature = ed25519::sign_arbitrary_bytes(&verifier_secret_key, bcs::to_bytes(&wrong_intent_id));

        // This should abort because signature was created for wrong intent_id
        let solver_payment = primary_fungible_store::withdraw(solver, offered_token_type, 50);
        intent_as_escrow::complete_escrow(
            solver,
            session,
            solver_payment,
            verifier_signature,
        );
    }

    #[test(
        aptos_framework = @0x1,
        user = @0xcafe,
        solver = @0xdead,
        _verifier = @0xbeef
    )]
    #[expected_failure(abort_code = 65539, location = fa_intent_with_oracle)] // error::invalid_argument(EINVALID_SIGNATURE)
    /// What is tested: a signature for one escrow intent_id cannot be replayed on another escrow
    /// Why: Enforce replay protection by binding verifier signatures to a single intent_id
    fun test_signature_replay_prevention(
        aptos_framework: &signer,
        user: &signer,
        solver: &signer,
        _verifier: &signer,
    ) {
        // Need enough tokens: 30 for escrow A + 30 for escrow B + 30 for solver payment = 90
        // Using smaller amounts to stay within test token supply limits (other tests use 100 max)
        let (offered_token_type, _) = test_utils::register_and_mint_tokens(aptos_framework, user, 90);

        // Give solver some of the source token type for payment
        let solver_payment_tokens = primary_fungible_store::withdraw(user, offered_token_type, 30);
        primary_fungible_store::deposit(signer::address_of(solver), solver_payment_tokens);

        let (verifier_secret_key, validated_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_pk);
        
        // Create escrow A with intent_id = @0x1
        let offered_asset_a = primary_fungible_store::withdraw(user, offered_token_type, 30);
        let reservation_a = intent_reservation::new_reservation(signer::address_of(solver));
        let _escrow_intent_a = intent_as_escrow::create_escrow(
            user,
            offered_asset_a,
            2, // offered_chain_id: connected chain where escrow is created
            verifier_public_key,
            timestamp::now_seconds() + 3600,
            @0x1, // Escrow A with intent_id = @0x1
            reservation_a,
            1, // desired_chain_id: hub chain where tokens are desired
        );
        
        // Create escrow B with intent_id = @0x2
        let offered_asset_b = primary_fungible_store::withdraw(user, offered_token_type, 30);
        let reservation_b = intent_reservation::new_reservation(signer::address_of(solver));
        let escrow_intent_b = intent_as_escrow::create_escrow(
            user,
            offered_asset_b,
            2, // offered_chain_id: connected chain where escrow is created
            verifier_public_key,
            timestamp::now_seconds() + 3600,
            @0x2, // Escrow B with intent_id = @0x2
            reservation_b,
            1, // desired_chain_id: hub chain where tokens are desired
        );
        
        // Start escrow session for escrow B
        let (escrowed_asset_b, session_b) = intent_as_escrow::start_escrow_session(solver, escrow_intent_b);
        primary_fungible_store::deposit(signer::address_of(solver), escrowed_asset_b);
        
        // Verifier creates a VALID signature for intent_id @0x1 (escrow A)
        let intent_id_a = @0x1;
        let valid_signature_for_a = ed25519::sign_arbitrary_bytes(&verifier_secret_key, bcs::to_bytes(&intent_id_a));

        // Try to use the signature for intent_id @0x1 on escrow B (which has intent_id @0x2)
        // This should fail because the signature is bound to @0x1, not @0x2
        let solver_payment = primary_fungible_store::withdraw(solver, offered_token_type, 30);
        intent_as_escrow::complete_escrow(
            solver,
            session_b,
            solver_payment,
            valid_signature_for_a, // Signature for @0x1 used on escrow with @0x2
        );
    }

    #[test(
        aptos_framework = @0x1,
        user = @0xcafe,
        solver = @0xdead,
        _verifier = @0xbeef
    )]
    #[expected_failure(abort_code = 327684, location = mvmt_intent::intent)] // error::permission_denied(ENOT_REVOCABLE)
    /// What is tested: attempting to revoke an escrow intent aborts with ENOT_REVOCABLE
    /// Why: Escrow intents must be non-revocable to guarantee solver safety
    fun test_escrow_revocation(
        aptos_framework: &signer,
        user: &signer,
        solver: &signer,
        _verifier: &signer,
    ) {
        let (offered_token_type, _) = test_utils::register_and_mint_tokens(aptos_framework, user, 100);
        let (_desired_token_type, _) = test_utils::register_and_mint_tokens(aptos_framework, solver, 100);

        let (_verifier_secret_key, validated_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_pk);
        
        let offered_asset = primary_fungible_store::withdraw(user, offered_token_type, 50);
        let reservation = intent_reservation::new_reservation(signer::address_of(solver));
        let escrow_intent = intent_as_escrow::create_escrow(
            user,
            offered_asset,
            2, // offered_chain_id: connected chain where escrow is created
            verifier_public_key,
            timestamp::now_seconds() + 3600,
            @0x1, // dummy intent_id for testing
            reservation, // Escrow must be reserved for a specific solver
            1, // desired_chain_id: hub chain where tokens are desired
        );
        
        // Requester tries to revoke the escrow directly - this should fail because escrow is non-revocable
        fa_intent_with_oracle::revoke_fa_intent(user, escrow_intent);
    }

    #[test(
        aptos_framework = @0x1,
        user = @0xcafe,
        solver = @0xbeef
    )]
    /// What is tested: create_escrow_from_fa locks tokens and creates an escrow intent
    /// Why: Verify the entry function correctly withdraws tokens and reserves solver
    fun test_create_escrow_from_fa(
        aptos_framework: &signer,
        user: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        // Create test fungible asset metadata for testing
        let (fa_metadata, _) = test_utils::register_and_mint_tokens(aptos_framework, user, 100);
        
        // Generate verifier key pair
        let (_, validated_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_pk);
        
        // Convert to vector<u8> for the wrapper function
        let verifier_public_key_bytes = ed25519::unvalidated_public_key_to_bytes(&verifier_public_key);
        
        // Test the wrapper function: create escrow from FA (must specify reserved solver)
        mvmt_intent::intent_as_escrow_entry::create_escrow_from_fa(
            user,
            fa_metadata,
            50,
            2, // offered_chain_id: connected chain where escrow is created
            verifier_public_key_bytes,
            timestamp::now_seconds() + 3600,
            @0x1, // dummy intent_id for testing
            signer::address_of(solver), // Reserved solver address
            1, // desired_chain_id: hub chain where tokens are desired
        );
        
        // Verify requester's balance decreased by 50
        assert!(primary_fungible_store::balance(signer::address_of(user), fa_metadata) == 50);
        
        // Verify escrow intent was created (it should exist)
        // Note: We can't easily verify the escrow intent object without more complex checks
    }
}
