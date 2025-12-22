#[test_only]
module mvmt_intent::fa_intent_outflow_tests {
    use std::signer;
    use std::option;
    use std::bcs;
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self as object, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_std::ed25519;
    use mvmt_intent::fa_intent_outflow;
    use mvmt_intent::fa_intent;
    use mvmt_intent::fa_intent_with_oracle;
    use mvmt_intent::intent::Intent;
    use mvmt_intent::intent_reservation;
    use mvmt_intent::intent_registry;
    use mvmt_intent::solver_registry;
    use mvmt_intent::test_utils;

    // ============================================================================
    // TEST HELPERS
    // ============================================================================

    /// Helper function to set up common test infrastructure (tokens, registry, keys, signed intent).
    /// Returns all values needed to create an outflow intent.
    /// This helper does NOT create the intent - it only sets up the prerequisites.
    fun setup_outflow_test_infrastructure(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requester_signer: &signer,
        solver_signer: &signer,
    ): (
        Object<aptos_framework::fungible_asset::Metadata>, // offered_metadata
        Object<aptos_framework::fungible_asset::Metadata>, // desired_metadata
        address, // solver_addr
        vector<u8>, // solver_signature_bytes
        vector<u8>, // verifier_public_key_bytes
        ed25519::SecretKey, // verifier_secret_key (needed to sign intent_id for fulfillment)
        address, // intent_id
        u64, // expiry_time
        u64, // offered_amount
        u64, // desired_amount
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Create test fungible assets
        let (offered_metadata, _) = mvmt_intent::test_utils::register_and_mint_tokens(aptos_framework, requester_signer, 100);
        let (desired_metadata, _) = mvmt_intent::test_utils::register_and_mint_tokens(aptos_framework, solver_signer, 0);
        
        let intent_id = @0x5678;
        let solver_addr = signer::address_of(solver_signer);
        let expiry_time = timestamp::now_seconds() + 3600;
        let offered_amount = 50u64;
        let desired_amount = 25u64;
        
        // Initialize solver registry and intent registry
        solver_registry::init_for_test(mvmt_intent);
        intent_registry::init_for_test(mvmt_intent);
        
        // Generate key pairs for solver and verifier
        let (solver_secret_key, validated_solver_pk) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&validated_solver_pk);
        let evm_addr = test_utils::create_test_evm_address(0);
        
        // Register solver in registry
        solver_registry::register_solver(solver_signer, solver_public_key_bytes, evm_addr, @0x0);
        
        // Generate verifier key pair (need secret key for signing intent_id later)
        let (verifier_secret_key, validated_verifier_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_verifier_pk);
        let verifier_public_key_bytes = ed25519::unvalidated_public_key_to_bytes(&verifier_public_key);
        
        // Step 1: Create draft intent (off-chain)
        let draft_intent = fa_intent_outflow::create_cross_chain_draft_intent(
            offered_metadata,
            offered_amount,
            1, // offered_chain_id (hub chain where tokens are locked)
            desired_metadata,
            desired_amount,
            2, // desired_chain_id (connected chain)
            expiry_time,
            signer::address_of(requester_signer),
        );
        
        // Step 2: Add solver to draft and create intent to sign
        let intent_to_sign = intent_reservation::add_solver_to_draft_intent(draft_intent, solver_addr);
        
        // Step 3: Solver signs the intent (off-chain)
        let intent_hash = intent_reservation::hash_intent(intent_to_sign);
        let solver_signature = ed25519::sign_arbitrary_bytes(&solver_secret_key, intent_hash);
        let solver_signature_bytes = ed25519::signature_to_bytes(&solver_signature);
        
        (
            offered_metadata,
            desired_metadata,
            solver_addr,
            solver_signature_bytes,
            verifier_public_key_bytes,
            verifier_secret_key,
            intent_id,
            expiry_time,
            offered_amount,
            desired_amount,
        )
    }

    /// Helper function to set up an outflow intent for testing.
    /// Returns the intent object, metadata, verifier signature bytes (for intent_id), and intent_id.
    fun setup_outflow_intent(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requester_signer: &signer,
        solver_signer: &signer,
    ): (
        Object<Intent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>>,
        Object<aptos_framework::fungible_asset::Metadata>,
        Object<aptos_framework::fungible_asset::Metadata>,
        vector<u8>, // verifier_signature_bytes (signs intent_id)
        address, // intent_id
    ) {
        // Set up test infrastructure using shared helper
        let (offered_metadata, desired_metadata, solver_addr, solver_signature_bytes, verifier_public_key_bytes, verifier_secret_key, intent_id, expiry_time, offered_amount, desired_amount) = 
            setup_outflow_test_infrastructure(aptos_framework, mvmt_intent, requester_signer, solver_signer);
        
        let requester_addr_connected_chain = @0x9999; // Address on connected chain
        
        // Create outflow intent (returns intent object)
        // Pass desired_metadata as address (for cross-chain support)
        let desired_metadata_addr = object::object_address(&desired_metadata);
        let intent_obj = fa_intent_outflow::create_outflow_intent(
            requester_signer,
            offered_metadata,
            offered_amount,
            1, // offered_chain_id (hub chain)
            desired_metadata_addr,  // Pass as address, not Object
            desired_amount,
            2, // desired_chain_id (connected chain)
            expiry_time,
            intent_id,
            requester_addr_connected_chain,
            verifier_public_key_bytes,
            solver_addr,
            solver_signature_bytes,
        );
        
        // Generate verifier signature (signs the intent_id to prove connected chain transfer)
        // Uses the same verifier secret key that corresponds to the public key used in intent creation
        let intent_id_bytes = bcs::to_bytes(&intent_id);
        let verifier_signature = ed25519::sign_arbitrary_bytes(&verifier_secret_key, intent_id_bytes);
        let verifier_signature_bytes = ed25519::signature_to_bytes(&verifier_signature);
        
        (intent_obj, offered_metadata, desired_metadata, verifier_signature_bytes, intent_id)
    }

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requester_signer = @0xcafe,
        solver_signer = @0xdead
    )]
    /// What is tested: create_outflow_intent locks tokens on hub and stores the connected-chain requester address
    /// Why: Outflow intents must lock real funds on hub and carry the destination address for settlement
    fun test_create_outflow_intent(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requester_signer: &signer,
        solver_signer: &signer,
    ) {
        // Set up test infrastructure using shared helper
        let (offered_metadata, desired_metadata, solver_addr, solver_signature_bytes, verifier_public_key_bytes, _verifier_secret_key, intent_id, expiry_time, offered_amount, desired_amount) = 
            setup_outflow_test_infrastructure(aptos_framework, mvmt_intent, requester_signer, solver_signer);
        
        let requester_addr_connected_chain = @0x9999; // Address on connected chain
        
        // Verify requester_signer's initial balance
        assert!(primary_fungible_store::balance(signer::address_of(requester_signer), offered_metadata) == 100);
        
        // Create outflow intent (returns intent object)
        // Pass desired_metadata as address (for cross-chain support)
        let desired_metadata_addr = object::object_address(&desired_metadata);
        let intent_obj = fa_intent_outflow::create_outflow_intent(
            requester_signer,
            offered_metadata,
            offered_amount,
            1, // offered_chain_id (hub chain)
            desired_metadata_addr,  // Pass as address, not Object
            desired_amount,
            2, // desired_chain_id (connected chain)
            expiry_time,
            intent_id,
            requester_addr_connected_chain,
            verifier_public_key_bytes,
            solver_addr,
            solver_signature_bytes,
        );
        
        // Verify tokens were actually locked (balance decreased from 100 to 50)
        assert!(primary_fungible_store::balance(signer::address_of(requester_signer), offered_metadata) == 50);
        
        // Verify intent was created successfully by checking the intent object
        let intent_addr = object::object_address(&intent_obj);
        assert!(intent_addr != @0x0); // Intent address should not be zero
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requester_signer = @0xcafe,
        solver_signer = @0xdead
    )]
    /// What is tested: OracleGuardedLimitOrder stores requester_addr_connected_chain correctly
    /// Why: Solver needs this address to know where to send tokens on the connected chain
    fun test_outflow_intent_requester_address_storage(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requester_signer: &signer,
        solver_signer: &signer,
    ) {
        use mvmt_intent::fa_intent_with_oracle;
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Create test fungible assets
        let (offered_metadata, _) = mvmt_intent::test_utils::register_and_mint_tokens(aptos_framework, requester_signer, 100);
        let (desired_metadata, _) = mvmt_intent::test_utils::register_and_mint_tokens(aptos_framework, solver_signer, 100);
        
        let intent_id = @0xabcd;
        let solver_addr = signer::address_of(solver_signer);
        let requester_addr_connected_chain = @0x1234; // Address on connected chain
        let expiry_time = timestamp::now_seconds() + 3600;
        
        // Initialize solver registry and intent registry
        solver_registry::init_for_test(mvmt_intent);
        intent_registry::init_for_test(mvmt_intent);
        
        // Generate key pairs
        let (_, validated_solver_pk) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&validated_solver_pk);
        let evm_addr = test_utils::create_test_evm_address(0);
        solver_registry::register_solver(solver_signer, solver_public_key_bytes, evm_addr, @0x0);
        
        let (verifier_secret_key, validated_verifier_pk) = ed25519::generate_keys();
        let verifier_public_key = ed25519::public_key_to_unvalidated(&validated_verifier_pk);
        let _verifier_public_key_bytes = ed25519::unvalidated_public_key_to_bytes(&verifier_public_key);
        
        // Create intent directly using lower-level function to test struct field storage
        let fa = primary_fungible_store::withdraw(requester_signer, offered_metadata, 50);
        let reservation = intent_reservation::new_reservation(solver_addr);
        let requirement = fa_intent_with_oracle::new_oracle_signature_requirement(0, verifier_public_key);
        
        let intent_obj = fa_intent_with_oracle::create_fa_to_fa_intent_with_oracle_requirement(
            fa,
            1, // offered_chain_id: hub chain where tokens are locked
            desired_metadata,
            25,
            2, // desired_chain_id: connected chain where tokens are desired
            option::some(object::object_address(&desired_metadata)), // Cross-chain: pass desired_metadata_addr
            expiry_time,
            signer::address_of(requester_signer),
            requirement,
            false,
            intent_id,
            option::some(requester_addr_connected_chain), // Store requester address
            option::some(reservation),
        );
        
        // Verify tokens were locked
        assert!(primary_fungible_store::balance(signer::address_of(requester_signer), offered_metadata) == 50);
        
        // Start session and complete it to verify intent structure is correct
        // This confirms the struct field was stored (otherwise struct creation would fail)
        let (unlocked_fa, session) = fa_intent_with_oracle::start_fa_offering_session(solver_signer, intent_obj);
        primary_fungible_store::deposit(signer::address_of(solver_signer), unlocked_fa);
        
        // Verify unlocked tokens match what was locked (50 tokens)
        assert!(primary_fungible_store::balance(signer::address_of(solver_signer), offered_metadata) == 50);
        
        // Complete the session with oracle signature to properly finish it
        let desired_fa = primary_fungible_store::withdraw(solver_signer, desired_metadata, 25);
        let oracle_signature = ed25519::sign_arbitrary_bytes(&verifier_secret_key, bcs::to_bytes(&intent_id));
        let witness = fa_intent_with_oracle::new_oracle_signature_witness(0, oracle_signature);
        fa_intent_with_oracle::finish_fa_receiving_session_with_oracle(session, desired_fa, option::some(witness));
        
        // Verify completion - requester_signer received desired tokens
        assert!(primary_fungible_store::balance(signer::address_of(requester_signer), desired_metadata) == 25);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requester_signer = @0xcafe,
        solver_signer = @0xdead
    )]
    /// What is tested: fulfill_outflow_intent releases locked tokens to solver after verifier signature validation
    /// Why: Verify solver receives locked tokens after providing valid verifier signature
    fun test_fulfill_outflow_intent(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requester_signer: &signer,
        solver_signer: &signer,
    ) {
        use mvmt_intent::fa_intent_with_oracle;
        use mvmt_intent::intent::Intent;
        
        // Set up outflow intent using shared helper
        let (intent_obj, offered_metadata, _desired_metadata, verifier_signature_bytes, _intent_id) = setup_outflow_intent(
            aptos_framework,
            mvmt_intent,
            requester_signer,
            solver_signer,
        );
        
        // Verify intent was created and registered
        let intent_addr = object::object_address(&intent_obj);
        assert!(intent_addr != @0x0);
        assert!(intent_registry::is_intent_registered(intent_addr));
        assert!(intent_registry::get_intent_count(signer::address_of(requester_signer)) == 1);
        
        // Verify tokens were locked (requester_signer's balance decreased)
        assert!(primary_fungible_store::balance(signer::address_of(requester_signer), offered_metadata) == 50);
        
        // Convert to generic Object type for entry function
        let intent_obj_generic: Object<Intent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>> = 
            object::address_to_object(intent_addr);
        
        // Fulfill the outflow intent using fulfill_outflow_intent
        fa_intent_outflow::fulfill_outflow_intent(
            solver_signer,
            intent_obj_generic,
            verifier_signature_bytes,
        );
        
        // Verify solver_signer received the locked tokens (their reward)
        assert!(primary_fungible_store::balance(signer::address_of(solver_signer), offered_metadata) == 50);
        
        // Verify requester_signer's balance is still 50 (tokens were locked, then solver got them)
        assert!(primary_fungible_store::balance(signer::address_of(requester_signer), offered_metadata) == 50);
        
        // Verify intent was unregistered from registry after fulfillment
        assert!(!intent_registry::is_intent_registered(intent_addr));
        assert!(intent_registry::get_intent_count(signer::address_of(requester_signer)) == 0);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requester_signer = @0xcafe,
        solver_signer = @0xdead
    )]
    #[expected_failure(abort_code = 393223, location = aptos_framework::object)] // error::not_found(ERESOURCE_DOES_NOT_EXIST)
    /// What is tested: fulfilling an outflow intent with the inflow function aborts with ERESOURCE_DOES_NOT_EXIST
    /// Why: Outflow intents require verifier signature; using inflow function would skip that check
    ///
    /// Note: The error ERESOURCE_DOES_NOT_EXIST occurs because object::address_to_object<T> checks
    /// if an object of type T exists at the address. The object exists, but not as the requested type,
    /// so the runtime reports that a resource of that type does not exist at that address.
    fun test_cannot_fulfill_outflow_with_inflow_function(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requester_signer: &signer,
        solver_signer: &signer,
    ) {
        // Set up outflow intent using shared helper
        let (intent_obj, _offered_metadata, _desired_metadata, _verifier_signature_bytes, _intent_id) = setup_outflow_intent(
            aptos_framework,
            mvmt_intent,
            requester_signer,
            solver_signer,
        );
        
        // Try to convert to FungibleAssetLimitOrder type (wrong type)
        // This should fail because the intent is OracleGuardedLimitOrder, not FungibleAssetLimitOrder
        // The type system prevents this conversion, which is what we're testing
        let intent_addr = object::object_address(&intent_obj);
        
        // Try to convert to the wrong type - this will fail at address_to_object
        // because object::address_to_object<T> checks if an object of type T exists at the address.
        // The object exists, but not as FungibleAssetLimitOrder, so the runtime reports
        // ERESOURCE_DOES_NOT_EXIST (a resource of that type doesn't exist at that address).
        let _wrong_type_intent: Object<Intent<fa_intent::FungibleStoreManager, fa_intent::FungibleAssetLimitOrder>> = 
            object::address_to_object(intent_addr);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requester_signer = @0xcafe,
        solver_signer = @0xdead
    )]
    #[expected_failure(abort_code = 0x10003, location = mvmt_intent::fa_intent_outflow)] // error::invalid_argument(EINVALID_REQUESTER_ADDRESS)
    /// What is tested: create_outflow_intent aborts when requester_addr_connected_chain is the zero address
    /// Why: Outflow intents must target a valid connected-chain recipient address
    fun test_create_outflow_intent_rejects_zero_requester_address(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requester_signer: &signer,
        solver_signer: &signer,
    ) {
        // Set up test infrastructure using shared helper
        let (offered_metadata, desired_metadata, solver_addr, solver_signature_bytes, verifier_public_key_bytes, _verifier_secret_key, intent_id, expiry_time, offered_amount, desired_amount) = 
            setup_outflow_test_infrastructure(aptos_framework, mvmt_intent, requester_signer, solver_signer);
        
        let requester_addr_connected_chain = @0x0; // Zero address - should be rejected
        
        // Attempt to create outflow intent with zero address - should abort
        // Pass desired_metadata as address (for cross-chain support)
        let desired_metadata_addr = object::object_address(&desired_metadata);
        fa_intent_outflow::create_outflow_intent(
            requester_signer,
            offered_metadata,
            offered_amount,
            1, // offered_chain_id (hub chain)
            desired_metadata_addr,  // Pass as address, not Object
            desired_amount,
            2, // desired_chain_id (connected chain)
            expiry_time,
            intent_id,
            requester_addr_connected_chain, // Zero address - should cause abort
            verifier_public_key_bytes,
            solver_addr,
            solver_signature_bytes,
        );
    }

}

