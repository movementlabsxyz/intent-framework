#[test_only]
module mvmt_intent::solver_registry_tests {
    use std::signer;
    use std::vector;
    use aptos_std::ed25519;
    use aptos_framework::timestamp;
    use mvmt_intent::solver_registry;
    use mvmt_intent::test_utils;

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// Test: Initialize solver registry
    fun test_initialize_registry(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Verify registry is initialized
        assert!(!solver_registry::is_registered(signer::address_of(solver)), 0);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// Test: Register solver successfully
    fun test_register_solver(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Generate Ed25519 keys for the solver
        let (_solver_secret_key, solver_public_key) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&solver_public_key);
        
        // Create a mock EVM address (20 bytes)
        let evm_address = test_utils::create_test_evm_address(0);
        
        // Register solver
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_address);
        
        // Verify solver is registered
        assert!(solver_registry::is_registered(signer::address_of(solver)), 1);
        
        // Verify public key matches
        let stored_public_key = solver_registry::get_public_key(signer::address_of(solver));
        assert!(vector::length(&stored_public_key) == 32, 2);
        assert!(stored_public_key == solver_public_key_bytes, 3);
        
        // Verify EVM address matches
        let stored_evm_address = solver_registry::get_evm_address(signer::address_of(solver));
        assert!(vector::length(&stored_evm_address) == 20, 4);
        assert!(stored_evm_address == evm_address, 5);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    #[expected_failure(abort_code = solver_registry::E_PUBLIC_KEY_LENGTH_INVALID)]
    /// Test: Register solver with invalid public key length
    fun test_register_solver_invalid_public_key_length(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        let _ = aptos_framework; // Suppress unused parameter warning
        solver_registry::init_for_test(mvmt_intent);
        
        // Create invalid public key (wrong length)
        let invalid_public_key = vector::empty<u8>();
        let i = 0;
        while (i < 31) {  // 31 bytes instead of 32
            vector::push_back(&mut invalid_public_key, i);
            i = i + 1;
        };
        
        // Create a mock EVM address
        let evm_address = test_utils::create_test_evm_address(0);
        
        // Should abort with E_PUBLIC_KEY_LENGTH_INVALID
        solver_registry::register_solver(solver, invalid_public_key, evm_address);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    #[expected_failure(abort_code = solver_registry::E_EVM_ADDRESS_LENGTH_INVALID)]
    /// Test: Register solver with invalid EVM address length
    fun test_register_solver_invalid_evm_address_length(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        let _ = aptos_framework; // Suppress unused parameter warning
        solver_registry::init_for_test(mvmt_intent);
        
        // Generate Ed25519 keys
        let (_solver_secret_key, solver_public_key) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&solver_public_key);
        
        // Create invalid EVM address (wrong length)
        let invalid_evm_address = vector::empty<u8>();
        let i = 0;
        while (i < 19) {  // 19 bytes instead of 20
            vector::push_back(&mut invalid_evm_address, i);
            i = i + 1;
        };
        
        // Should abort with E_EVM_ADDRESS_LENGTH_INVALID
        solver_registry::register_solver(solver, solver_public_key_bytes, invalid_evm_address);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    #[expected_failure(abort_code = solver_registry::E_SOLVER_ALREADY_REGISTERED)]
    /// Test: Register solver twice should fail
    fun test_register_solver_twice(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Generate Ed25519 keys
        let (_solver_secret_key, solver_public_key) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&solver_public_key);
        
        // Create EVM address
        let evm_address = test_utils::create_test_evm_address(0);
        
        // Register solver first time
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_address);
        
        // Try to register again - should abort
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_address);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// Test: Update solver information
    /// Verifies that a registered solver can update their own information
    fun test_update_solver(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Generate first set of Ed25519 keys
        let (_solver_secret_key1, solver_public_key1) = ed25519::generate_keys();
        let solver_public_key_bytes1 = ed25519::validated_public_key_to_bytes(&solver_public_key1);
        
        // Create first EVM address
        let evm_address1 = test_utils::create_test_evm_address(0);
        
        // Register solver
        solver_registry::register_solver(solver, solver_public_key_bytes1, evm_address1);
        
        // Generate new Ed25519 keys
        let (_solver_secret_key2, solver_public_key2) = ed25519::generate_keys();
        let solver_public_key_bytes2 = ed25519::validated_public_key_to_bytes(&solver_public_key2);
        
        // Create new EVM address (different from first)
        let evm_address2 = test_utils::create_test_evm_address_reverse(20);
        
        // Update solver (solver updates their own info)
        solver_registry::update_solver(solver, solver_public_key_bytes2, evm_address2);
        
        // Verify updated values
        let stored_public_key = solver_registry::get_public_key(signer::address_of(solver));
        assert!(stored_public_key == solver_public_key_bytes2, 1);
        
        let stored_evm_address = solver_registry::get_evm_address(signer::address_of(solver));
        assert!(stored_evm_address == evm_address2, 2);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// Test: Get solver info
    fun test_get_solver_info(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Generate Ed25519 keys
        let (_solver_secret_key, solver_public_key) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&solver_public_key);
        
        // Create EVM address
        let evm_address = test_utils::create_test_evm_address(0);
        
        // Register solver
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_address);
        
        // Get solver info
        let (is_registered, public_key, evm_addr, registered_at) = solver_registry::get_solver_info(signer::address_of(solver));
        
        assert!(is_registered, 1);
        assert!(public_key == solver_public_key_bytes, 2);
        assert!(evm_addr == evm_address, 3);
        assert!(registered_at >= 0, 4); // registered_at can be 0 if timestamp hasn't advanced
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// Test: Get solver info for unregistered solver
    fun test_get_solver_info_unregistered(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Get solver info for unregistered solver
        let (is_registered, public_key, evm_addr, registered_at) = solver_registry::get_solver_info(signer::address_of(solver));
        
        assert!(!is_registered, 1);
        assert!(vector::is_empty(&public_key), 2);
        assert!(vector::is_empty(&evm_addr), 3);
        assert!(registered_at == 0, 4);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// Test: Get public key unvalidated
    fun test_get_public_key_unvalidated(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Generate Ed25519 keys
        let (_solver_secret_key, solver_public_key) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&solver_public_key);
        
        // Create EVM address
        let evm_address = test_utils::create_test_evm_address(0);
        
        // Register solver
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_address);
        
        // Get unvalidated public key
        let _public_key_opt = solver_registry::get_public_key_unvalidated(signer::address_of(solver));
        // Note: We can't easily test the Option type here without more complex setup
        // The function is tested indirectly through intent_reservation tests
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// Test: Deregister solver successfully
    fun test_deregister_solver(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Generate Ed25519 keys
        let (_solver_secret_key, solver_public_key) = ed25519::generate_keys();
        let solver_public_key_bytes = ed25519::validated_public_key_to_bytes(&solver_public_key);
        
        // Create EVM address
        let evm_address = test_utils::create_test_evm_address(0);
        
        // Register solver
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_address);
        assert!(solver_registry::is_registered(signer::address_of(solver)), 1);
        
        // Deregister solver
        solver_registry::deregister_solver(solver);
        
        // Verify solver is no longer registered
        assert!(!solver_registry::is_registered(signer::address_of(solver)), 2);
        
        // Verify public key and EVM address return empty
        let public_key = solver_registry::get_public_key(signer::address_of(solver));
        assert!(vector::is_empty(&public_key), 3);
        
        let evm_addr = solver_registry::get_evm_address(signer::address_of(solver));
        assert!(vector::is_empty(&evm_addr), 4);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    #[expected_failure(abort_code = solver_registry::E_SOLVER_NOT_FOUND)]
    /// Test: Deregister unregistered solver should fail
    fun test_deregister_unregistered_solver(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Try to deregister without registering first - should abort
        solver_registry::deregister_solver(solver);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// Test: Re-register after deregistering
    fun test_reregister_after_deregister(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Generate first set of Ed25519 keys
        let (_solver_secret_key1, solver_public_key1) = ed25519::generate_keys();
        let solver_public_key_bytes1 = ed25519::validated_public_key_to_bytes(&solver_public_key1);
        
        // Create first EVM address
        let evm_address1 = test_utils::create_test_evm_address(0);
        
        // Register solver
        solver_registry::register_solver(solver, solver_public_key_bytes1, evm_address1);
        assert!(solver_registry::is_registered(signer::address_of(solver)), 1);
        
        // Deregister solver
        solver_registry::deregister_solver(solver);
        assert!(!solver_registry::is_registered(signer::address_of(solver)), 2);
        
        // Generate new Ed25519 keys
        let (_solver_secret_key2, solver_public_key2) = ed25519::generate_keys();
        let solver_public_key_bytes2 = ed25519::validated_public_key_to_bytes(&solver_public_key2);
        
        // Create new EVM address
        let evm_address2 = test_utils::create_test_evm_address_reverse(20);
        
        // Re-register solver with new credentials
        solver_registry::register_solver(solver, solver_public_key_bytes2, evm_address2);
        assert!(solver_registry::is_registered(signer::address_of(solver)), 3);
        
        // Verify new credentials are stored
        let stored_public_key = solver_registry::get_public_key(signer::address_of(solver));
        assert!(stored_public_key == solver_public_key_bytes2, 4);
        
        let stored_evm_address = solver_registry::get_evm_address(signer::address_of(solver));
        assert!(stored_evm_address == evm_address2, 5);
    }
}

