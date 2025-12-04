#[test_only]
module mvmt_intent::fa_intent_inflow_tests {
    use std::signer;
    use std::option;
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self as object, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::FungibleAsset;
    use aptos_std::ed25519;
    use mvmt_intent::fa_intent_inflow;
    use mvmt_intent::fa_intent;
    use mvmt_intent::intent::Intent;
    use mvmt_intent::intent_reservation;
    use mvmt_intent::solver_registry;
    use mvmt_intent::test_utils;

    // ============================================================================
    // TEST HELPERS
    // ============================================================================

    /// Helper function to set up an inflow intent for testing.
    /// Returns the intent object and metadata for verification.
    fun setup_inflow_intent(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requestor: &signer,
        solver: &signer,
    ): (
        Object<Intent<fa_intent::FungibleStoreManager, fa_intent::FungibleAssetLimitOrder>>,
        Object<aptos_framework::fungible_asset::Metadata>,
        Object<aptos_framework::fungible_asset::Metadata>,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Create test fungible assets
        let (offered_metadata, _) = mvmt_intent::test_utils::register_and_mint_tokens(aptos_framework, requestor, 0);
        let (desired_metadata, _) = mvmt_intent::test_utils::register_and_mint_tokens(aptos_framework, solver, 100);
        
        let intent_id = @0x5678;
        let solver_address = signer::address_of(solver);
        let expiry_time = timestamp::now_seconds() + 3600;
        
        // Initialize solver registry
        solver_registry::init_for_test(mvmt_intent);
        
        // Generate key pair for solver
        let (solver_secret_key, validated_solver_pk) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&validated_solver_pk);
        let evm_address = test_utils::create_test_evm_address(0);
        
        // Register solver in registry
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_address, @0x0);
        
        // Step 1: Create draft intent (off-chain)
        let draft_intent = fa_intent_inflow::create_cross_chain_draft_intent(
            offered_metadata,
            100, // offered_amount (locked on connected chain)
            2, // offered_chain_id (connected chain)
            desired_metadata,
            100, // desired_amount
            1, // desired_chain_id (hub chain)
            expiry_time,
            signer::address_of(requestor),
        );
        
        // Step 2: Add solver to draft and create intent to sign
        let intent_to_sign = intent_reservation::add_solver_to_draft_intent(draft_intent, solver_address);
        
        // Step 3: Solver signs the intent (off-chain)
        let intent_hash = intent_reservation::hash_intent(intent_to_sign);
        let solver_signature = ed25519::sign_arbitrary_bytes(&solver_secret_key, intent_hash);
        let solver_signature_bytes = ed25519::signature_to_bytes(&solver_signature);
        
        // Step 4: Create inflow intent (returns intent object)
        // Pass offered_metadata as address (for cross-chain support)
        let offered_metadata_addr = object::object_address(&offered_metadata);
        let intent_obj = fa_intent_inflow::create_inflow_intent(
            requestor,
            offered_metadata_addr,  // Pass as address, not Object
            100, // offered_amount
            2, // offered_chain_id (connected chain)
            desired_metadata,
            100, // desired_amount
            1, // desired_chain_id (hub chain)
            expiry_time,
            intent_id,
            solver_address,
            solver_signature_bytes,
        );
        
        (intent_obj, offered_metadata, desired_metadata)
    }

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requestor = @0xcafe,
        solver = @0xdead
    )]
    /// Test: Inflow intent creation
    /// Verifies that create_inflow_intent:
    /// 1. Locks 0 tokens on hub chain (unlike outflow which locks actual tokens)
    /// 2. Creates a FungibleAssetLimitOrder intent (no verifier signature required)
    /// 3. Creates an intent that can be retrieved and used
    fun test_create_inflow_intent(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requestor: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Create test fungible assets
        let (offered_metadata, _) = mvmt_intent::test_utils::register_and_mint_tokens(aptos_framework, requestor, 0);
        let (desired_metadata, _) = mvmt_intent::test_utils::register_and_mint_tokens(aptos_framework, solver, 0);
        
        let intent_id = @0x5678;
        let solver_address = signer::address_of(solver);
        let expiry_time = timestamp::now_seconds() + 3600;
        let offered_amount = 100u64;
        let desired_amount = 100u64;
        
        // Initialize solver registry
        solver_registry::init_for_test(mvmt_intent);
        
        // Generate key pairs for solver
        let (solver_secret_key, validated_solver_pk) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&validated_solver_pk);
        let evm_address = test_utils::create_test_evm_address(0);
        
        // Register solver in registry
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_address, @0x0);
        
        // Step 1: Create draft intent (off-chain)
        let draft_intent = fa_intent_inflow::create_cross_chain_draft_intent(
            offered_metadata,
            offered_amount,
            2, // offered_chain_id (connected chain)
            desired_metadata,
            desired_amount,
            1, // desired_chain_id (hub chain)
            expiry_time,
            signer::address_of(requestor),
        );
        
        // Step 2: Add solver to draft and create intent to sign
        let intent_to_sign = intent_reservation::add_solver_to_draft_intent(draft_intent, solver_address);
        
        // Step 3: Solver signs the intent (off-chain)
        let intent_hash = intent_reservation::hash_intent(intent_to_sign);
        let solver_signature = ed25519::sign_arbitrary_bytes(&solver_secret_key, intent_hash);
        let solver_signature_bytes = ed25519::signature_to_bytes(&solver_signature);
        
        // Step 4: Verify requestor's initial balance (should be 0 for offered_metadata)
        assert!(primary_fungible_store::balance(signer::address_of(requestor), offered_metadata) == 0);
        
        // Step 5: Create inflow intent using public function
        // Pass offered_metadata as address (for cross-chain support)
        let offered_metadata_addr = object::object_address(&offered_metadata);
        let intent_obj = fa_intent_inflow::create_inflow_intent(
            requestor,
            offered_metadata_addr,  // Pass as address, not Object
            offered_amount,
            2, // offered_chain_id (connected chain)
            desired_metadata,
            desired_amount,
            1, // desired_chain_id (hub chain)
            expiry_time,
            intent_id,
            solver_address,
            solver_signature_bytes,
        );
        
        // Step 6: Verify 0 tokens were locked (balance unchanged, still 0)
        assert!(primary_fungible_store::balance(signer::address_of(requestor), offered_metadata) == 0);
        
        // Step 7: Verify intent was created by checking the intent address
        let intent_address = object::object_address(&intent_obj);
        assert!(intent_address != @0x0);
        
        // Step 8: Verify intent structure is correct by checking it's a valid Intent
        // The fact that we got a valid address and object confirms creation was successful
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requestor = @0xcafe,
        solver = @0xdead
    )]
    /// Test: Cross-chain intent fulfillment
    /// Verifies that a solver can fulfill a cross-chain intent where the requestor
    /// has 0 tokens locked on the hub chain (tokens are in escrow on a different chain).
    /// This is Step 3 of the cross-chain escrow flow.
    fun test_fulfill_cross_chain_intent(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requestor: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Create test fungible assets for cross-chain swap
        // Source FA (locked on connected chain) and desired FA (requested on hub chain)
        let (offered_metadata, _) = mvmt_intent::test_utils::register_and_mint_tokens(aptos_framework, requestor, 0);
        let (desired_metadata, _desired_mint_ref) = mvmt_intent::test_utils::register_and_mint_tokens(aptos_framework, solver, 100);
        
        // Requestor creates a cross-chain intent (has 0 tokens locked)
        // Use a dummy intent_id for testing (in real scenarios this links cross-chain intents)
        let dummy_intent_id = @0x1234;
        let solver_address = signer::address_of(solver);
        let expiry_time = timestamp::now_seconds() + 3600;
        
        // Initialize solver registry
        solver_registry::init_for_test(mvmt_intent);
        
        // Generate key pair for solver (simulating off-chain key generation)
        let (solver_secret_key, validated_public_key) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&validated_public_key);
        let evm_address = test_utils::create_test_evm_address(0);
        
        // Register solver in registry
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_address, @0x0);
        
        // Step 1: Create draft intent (off-chain)
        let draft_intent = fa_intent_inflow::create_cross_chain_draft_intent(
            offered_metadata,
            100, // offered_amount
            2, // offered_chain_id (chain where escrow is - connected chain)
            desired_metadata,
            100, // desired_amount
            1, // desired_chain_id (hub chain)
            expiry_time,
            signer::address_of(requestor),
        );
        
        // Step 2: Add solver to draft and create intent to sign
        let intent_to_sign = intent_reservation::add_solver_to_draft_intent(draft_intent, solver_address);
        
        // Step 3: Solver signs the intent (off-chain)
        let intent_hash = intent_reservation::hash_intent(intent_to_sign);
        let solver_signature = ed25519::sign_arbitrary_bytes(&solver_secret_key, intent_hash);
        let solver_signature_bytes = ed25519::signature_to_bytes(&solver_signature);
        
        // Step 4: Requestor creates intent on-chain with solver's signature using registry
        let reservation_result = intent_reservation::verify_and_create_reservation_from_registry(
            intent_to_sign,
            solver_signature_bytes,
        );
        assert!(option::is_some(&reservation_result), 0);
        
        // Create the intent with the verified reservation
        let fa: FungibleAsset = primary_fungible_store::withdraw(requestor, offered_metadata, 0);
        let intent_obj = fa_intent::create_fa_to_fa_intent(
            fa,
            1, // offered_chain_id
            desired_metadata,
            100,
            1, // desired_chain_id
            expiry_time,
            signer::address_of(requestor),
            reservation_result, // Reserved for solver
            false, // Non-revocable
            option::some(dummy_intent_id),
        );
        let intent_address = object::object_address(&intent_obj);
        
        // Verify intent was created
        assert!(intent_address != @0x0);
        
        // Convert address to object reference (generic Object type)
        let intent_obj = object::address_to_object(intent_address);
        
        // Solver fulfills the intent using the entry function
        // Note: This calls start_fa_offering_session (unlocks 0 tokens), 
        // withdraws payment tokens, and finishes the session
        fa_intent_inflow::fulfill_inflow_intent(
            solver,
            intent_obj,
            100, // Provides 100 tokens
        );
        
        // Verify requestor received the tokens
        assert!(primary_fungible_store::balance(signer::address_of(requestor), desired_metadata) == 100);
        
        // Verify solver's balance decreased (100 - 100 = 0)
        assert!(primary_fungible_store::balance(signer::address_of(solver), desired_metadata) == 0);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requestor = @0xcafe,
        solver = @0xdead
    )]
    /// Test: Inflow intent creation and fulfillment end-to-end
    /// Verifies that create_inflow_intent creates an intent correctly,
    /// and that fulfill_inflow_intent can fulfill it.
    fun test_fulfill_inflow_intent(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requestor: &signer,
        solver: &signer,
    ) {
        // Set up inflow intent using shared helper
        let (intent_obj, _offered_metadata, desired_metadata) = setup_inflow_intent(
            aptos_framework,
            mvmt_intent,
            requestor,
            solver,
        );
        
        // Verify intent was created
        let intent_address = object::object_address(&intent_obj);
        assert!(intent_address != @0x0);
        
        // Convert to generic Object type for entry function
        let intent_obj_generic = object::address_to_object(intent_address);
        
        // Fulfill the inflow intent using fulfill_inflow_intent
        fa_intent_inflow::fulfill_inflow_intent(
            solver,
            intent_obj_generic,
            100, // Provides 100 tokens
        );
        
        // Verify requestor received the tokens
        assert!(primary_fungible_store::balance(signer::address_of(requestor), desired_metadata) == 100);
        
        // Verify solver's balance decreased (100 - 100 = 0)
        assert!(primary_fungible_store::balance(signer::address_of(solver), desired_metadata) == 0);
    }

    #[test(
        aptos_framework = @0x1,
        mvmt_intent = @0x123,
        requestor = @0xcafe,
        solver = @0xdead
    )]
    #[expected_failure(abort_code = 393223, location = aptos_framework::object)] // error::not_found(ERESOURCE_DOES_NOT_EXIST)
    /// Test: Cannot fulfill inflow intent with fulfill_outflow_intent
    /// Verifies type safety - an inflow intent (FungibleAssetLimitOrder) cannot be fulfilled
    /// using fulfill_outflow_intent which expects OracleGuardedLimitOrder.
    /// 
    /// Note: The error ERESOURCE_DOES_NOT_EXIST occurs because object::address_to_object<T> checks
    /// if an object of type T exists at the address. The object exists, but not as the requested type,
    /// so the runtime reports that a resource of that type does not exist at that address.
    fun test_cannot_fulfill_inflow_with_outflow_function(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        requestor: &signer,
        solver: &signer,
    ) {
        use mvmt_intent::fa_intent_with_oracle;
        use mvmt_intent::intent::Intent;
        
        // Set up inflow intent using shared helper
        let (intent_obj, _offered_metadata, _desired_metadata) = setup_inflow_intent(
            aptos_framework,
            mvmt_intent,
            requestor,
            solver,
        );
        
        // Try to convert to OracleGuardedLimitOrder type (wrong type)
        // This should fail because the intent is FungibleAssetLimitOrder, not OracleGuardedLimitOrder
        // The type system prevents this conversion, which is what we're testing
        let intent_address = object::object_address(&intent_obj);
        
        // Try to convert to the wrong type - this will fail at address_to_object
        // because object::address_to_object<T> checks if an object of type T exists at the address.
        // The object exists, but not as OracleGuardedLimitOrder, so the runtime reports
        // ERESOURCE_DOES_NOT_EXIST (a resource of that type doesn't exist at that address).
        let _wrong_type_intent: Object<Intent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>> = 
            object::address_to_object(intent_address);
    }

    #[test(
        aptos_framework = @0x1,
        requestor = @0xcafe,
        solver = @0xdead
    )]
    #[expected_failure(abort_code = 65537, location = mvmt_intent::fa_intent)] // error::invalid_argument(EAMOUNT_NOT_MEET)
    /// Test: Cross-chain intent fulfillment with insufficient amount
    /// Verifies that fulfillment fails when provided_amount < desired_amount.
    ///
    /// Expected behavior: Fulfillment fails with EAMOUNT_NOT_MEET when provided_amount < desired_amount.
    ///
    /// Actual validation is in fa_intent::finish_fa_receiving_session_with_event()
    /// which asserts: provided_amount >= argument.desired_amount
    fun test_fulfill_cross_chain_intent_insufficient_amount(
        aptos_framework: &signer,
        requestor: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Create test fungible assets for cross-chain swap
        let (offered_metadata, _) = mvmt_intent::test_utils::register_and_mint_tokens(aptos_framework, requestor, 0);
        let (desired_metadata, _desired_mint_ref) = mvmt_intent::test_utils::register_and_mint_tokens(aptos_framework, solver, 100);
        
        // Requestor creates a cross-chain intent wanting 1000 tokens
        let dummy_intent_id = @0x123;
        let solver_address = signer::address_of(solver);
        let expiry_time = timestamp::now_seconds() + 3600;
        
        // NOTE: In Move tests, we cannot extract the private key from a &signer to sign arbitrary data.
        // verify_and_create_reservation() gets the public key from account::get_authentication_key(solver),
        // but we can't get the matching private key from the signer to create a valid signature.
        // For this test, we use intent_reservation::new_reservation to bypass signature verification.
        let reservation = intent_reservation::new_reservation(solver_address);
        
        // Create the intent directly (bypassing signature verification for testing)
        let fa: FungibleAsset = primary_fungible_store::withdraw(requestor, offered_metadata, 0);
        let intent_obj = fa_intent::create_fa_to_fa_intent(
            fa,
            1, // offered_chain_id
            desired_metadata,
            1000,
            1, // desired_chain_id
            expiry_time,
            signer::address_of(requestor),
            option::some(reservation), // Reserved for solver
            false, // Non-revocable
            option::some(dummy_intent_id),
        );
        let intent_address = object::object_address(&intent_obj);
        
        // Convert address to object reference
        let intent_obj = object::address_to_object(intent_address);
        
        // Solver tries to fulfill with insufficient amount (50 < 1000)
        // This should fail with EAMOUNT_NOT_MEET
        fa_intent_inflow::fulfill_inflow_intent(
            solver,
            intent_obj,
            50, // Provides only 50 tokens (insufficient! Needs 1000)
        );
    }

}

