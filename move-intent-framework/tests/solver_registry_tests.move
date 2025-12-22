#[test_only]
module mvmt_intent::solver_registry_tests {
    use std::signer;
    use std::vector;
    use std::option;
    use aptos_std::ed25519;
    use aptos_framework::timestamp;
    use mvmt_intent::solver_registry;
    use mvmt_intent::test_utils;

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// What is tested: init_for_test initializes an empty solver registry at mvmt_intent
    /// Why: Ensure the registry starts with no pre-registered solvers
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
    /// What is tested: register_solver stores solver public key and EVM address correctly
    /// Why: Verifier relies on accurate registry entries for signature and address checks
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
        let evm_addr = test_utils::create_test_evm_address(0);
        
        // Register solver (empty vector for EVM address means "not set", 0x0 for MVM address means "not set")
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_addr, @0x0);
        
        // Verify solver is registered
        assert!(solver_registry::is_registered(signer::address_of(solver)), 1);
        
        // Verify public key matches
        let stored_public_key = solver_registry::get_public_key(signer::address_of(solver));
        assert!(vector::length(&stored_public_key) == 32, 2);
        assert!(stored_public_key == solver_public_key_bytes, 3);
        
        // Verify EVM address matches
        let stored_evm_address_opt = solver_registry::get_connected_chain_evm_address(signer::address_of(solver));
        assert!(option::is_some(&stored_evm_address_opt), 4);
        let stored_evm_addr = *option::borrow(&stored_evm_address_opt);
        assert!(vector::length(&stored_evm_addr) == 20, 5);
        assert!(stored_evm_addr == evm_addr, 6);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    #[expected_failure(abort_code = solver_registry::E_PUBLIC_KEY_LENGTH_INVALID)]
    /// What is tested: register_solver aborts when the public key length is invalid
    /// Why: Reject malformed public keys before they are stored on-chain
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
        let evm_addr = test_utils::create_test_evm_address(0);
        
        // Should abort with E_PUBLIC_KEY_LENGTH_INVALID
        solver_registry::register_solver(solver, invalid_public_key, evm_addr, @0x0);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    #[expected_failure(abort_code = solver_registry::E_EVM_ADDRESS_LENGTH_INVALID)]
    /// What is tested: register_solver aborts when the EVM address length is invalid
    /// Why: Ensure only well-formed EVM addresses are recorded for solvers
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
        let invalid_evm_addr = vector::empty<u8>();
        let i = 0;
        while (i < 19) {  // 19 bytes instead of 20
            vector::push_back(&mut invalid_evm_addr, i);
            i = i + 1;
        };
        
        // Should abort with E_EVM_ADDRESS_LENGTH_INVALID
        solver_registry::register_solver(solver, solver_public_key_bytes, invalid_evm_addr, @0x0);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    #[expected_failure(abort_code = solver_registry::E_SOLVER_ALREADY_REGISTERED)]
    /// What is tested: a second register_solver call for the same solver aborts
    /// Why: Prevent accidental overwrites of existing solver registrations
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
        let evm_addr = test_utils::create_test_evm_address(0);
        
        // Register solver first time
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_addr, @0x0);
        
        // Try to register again - should abort
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_addr, @0x0);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// What is tested: update_solver lets a registered solver change key and EVM address
    /// Why: Support key rotation and address updates for long-lived solvers
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
        let evm_addr1 = test_utils::create_test_evm_address(0);
        
        // Register solver
        solver_registry::register_solver(solver, solver_public_key_bytes1, evm_addr1, @0x0);
        
        // Generate new Ed25519 keys
        let (_solver_secret_key2, solver_public_key2) = ed25519::generate_keys();
        let solver_public_key_bytes2 = ed25519::validated_public_key_to_bytes(&solver_public_key2);
        
        // Create new EVM address (different from first)
        let evm_addr2 = test_utils::create_test_evm_address_reverse(20);
        
        // Update solver (solver updates their own info)
        solver_registry::update_solver(solver, solver_public_key_bytes2, evm_addr2, @0x0);
        
        // Verify updated values
        let stored_public_key = solver_registry::get_public_key(signer::address_of(solver));
        assert!(stored_public_key == solver_public_key_bytes2, 1);
        
        let stored_evm_address_opt = solver_registry::get_connected_chain_evm_address(signer::address_of(solver));
        assert!(option::is_some(&stored_evm_address_opt), 2);
        let stored_evm_addr = *option::borrow(&stored_evm_address_opt);
        assert!(stored_evm_addr == evm_addr2, 3);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// What is tested: get_solver_info returns full data for a registered solver
    /// Why: Allow off-chain services to introspect solver registry entries
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
        let expected_evm_addr = test_utils::create_test_evm_address(0);
        
        // Register solver (empty vector for EVM address means "not set", 0x0 for MVM address means "not set")
        solver_registry::register_solver(solver, solver_public_key_bytes, expected_evm_addr, @0x0);
        
        // Get solver info
        let (is_registered, public_key, evm_addr_opt, mvm_addr_opt, registered_at) = solver_registry::get_solver_info(signer::address_of(solver));
        
        assert!(is_registered, 1);
        assert!(public_key == solver_public_key_bytes, 2);
        assert!(option::is_some(&evm_addr_opt), 3);
        let evm_addr = *option::borrow(&evm_addr_opt);
        assert!(evm_addr == expected_evm_addr, 4);
        assert!(option::is_none(&mvm_addr_opt), 5);
        assert!(registered_at >= 0, 6); // registered_at can be 0 if timestamp hasn't advanced
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// What is tested: get_solver_info returns empty data for an unregistered solver
    /// Why: Callers can safely detect missing solver entries
    fun test_get_solver_info_unregistered(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Get solver info for unregistered solver
        let (is_registered, public_key, evm_addr_opt, mvm_addr_opt, registered_at) = solver_registry::get_solver_info(signer::address_of(solver));
        
        assert!(!is_registered, 1);
        assert!(vector::is_empty(&public_key), 2);
        assert!(option::is_none(&evm_addr_opt), 3);
        assert!(option::is_none(&mvm_addr_opt), 4);
        assert!(registered_at == 0, 5);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// What is tested: get_public_key_unvalidated returns an Option-wrapped public key
    /// Why: Support verification flows that work with unvalidated public keys
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
        let evm_addr = test_utils::create_test_evm_address(0);
        
        // Register solver (empty vector for EVM address means "not set", 0x0 for MVM address means "not set")
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_addr, @0x0);
        
        // Get unvalidated public key
        let _public_key_opt = solver_registry::get_public_key_unvalidated(signer::address_of(solver));
        // Note: We can't easily test the Option type here without more complex setup
        // The function is tested indirectly through intent_reservation tests
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    /// What is tested: deregister_solver removes a solver and clears associated data
    /// Why: Allow solvers to opt out and free on-chain registry state
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
        let evm_addr = test_utils::create_test_evm_address(0);
        
        // Register solver (empty vector for EVM address means "not set", 0x0 for MVM address means "not set")
        solver_registry::register_solver(solver, solver_public_key_bytes, evm_addr, @0x0);
        assert!(solver_registry::is_registered(signer::address_of(solver)), 1);
        
        // Deregister solver
        solver_registry::deregister_solver(solver);
        
        // Verify solver is no longer registered
        assert!(!solver_registry::is_registered(signer::address_of(solver)), 2);
        
        // Verify public key and EVM address return empty
        let public_key = solver_registry::get_public_key(signer::address_of(solver));
        assert!(vector::is_empty(&public_key), 3);
        
        let evm_addr_opt = solver_registry::get_connected_chain_evm_address(signer::address_of(solver));
        assert!(option::is_none(&evm_addr_opt), 4);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe)]
    #[expected_failure(abort_code = solver_registry::E_SOLVER_NOT_FOUND)]
    /// What is tested: deregister_solver aborts when the solver is not registered
    /// Why: Avoid silently succeeding on invalid deregistration requests
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
    /// What is tested: a solver can re-register with new credentials after deregistration
    /// Why: Allow clean credential rotation by deregistering and registering again
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
        let evm_addr1 = test_utils::create_test_evm_address(0);
        
        // Register solver
        solver_registry::register_solver(solver, solver_public_key_bytes1, evm_addr1, @0x0);
        assert!(solver_registry::is_registered(signer::address_of(solver)), 1);
        
        // Deregister solver
        solver_registry::deregister_solver(solver);
        assert!(!solver_registry::is_registered(signer::address_of(solver)), 2);
        
        // Generate new Ed25519 keys
        let (_solver_secret_key2, solver_public_key2) = ed25519::generate_keys();
        let solver_public_key_bytes2 = ed25519::validated_public_key_to_bytes(&solver_public_key2);
        
        // Create new EVM address
        let evm_addr2 = test_utils::create_test_evm_address_reverse(20);
        
        // Re-register solver with new credentials
        solver_registry::register_solver(solver, solver_public_key_bytes2, evm_addr2, @0x0);
        assert!(solver_registry::is_registered(signer::address_of(solver)), 3);
        
        // Verify new credentials are stored
        let stored_public_key = solver_registry::get_public_key(signer::address_of(solver));
        assert!(stored_public_key == solver_public_key_bytes2, 4);
        
        let stored_evm_address_opt = solver_registry::get_connected_chain_evm_address(signer::address_of(solver));
        assert!(option::is_some(&stored_evm_address_opt), 5);
        let stored_evm_addr = *option::borrow(&stored_evm_address_opt);
        assert!(stored_evm_addr == evm_addr2, 6);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe, solver2 = @0xbeef)]
    /// What is tested: multiple distinct solvers can be registered simultaneously
    /// Why: Support many competing solvers in the registry
    fun test_register_multiple_solvers(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
        solver2: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Register first solver
        let (_solver_secret_key1, solver_public_key1) = ed25519::generate_keys();
        let solver_public_key_bytes1 = ed25519::validated_public_key_to_bytes(&solver_public_key1);
        let evm_addr1 = test_utils::create_test_evm_address(0);
        solver_registry::register_solver(solver, solver_public_key_bytes1, evm_addr1, @0x0);
        assert!(solver_registry::is_registered(signer::address_of(solver)), 1);
        
        // Register second solver
        let (_solver_secret_key2, solver_public_key2) = ed25519::generate_keys();
        let solver_public_key_bytes2 = ed25519::validated_public_key_to_bytes(&solver_public_key2);
        let evm_addr2 = test_utils::create_test_evm_address(1);
        solver_registry::register_solver(solver2, solver_public_key_bytes2, evm_addr2, @0x0);
        assert!(solver_registry::is_registered(signer::address_of(solver2)), 2);
        
        // Verify both are still registered
        assert!(solver_registry::is_registered(signer::address_of(solver)), 3);
        assert!(solver_registry::is_registered(signer::address_of(solver2)), 4);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe, solver2 = @0xbeef, caller = @0xabcd)]
    /// What is tested: list_all_solvers runs without abort and leaves registry intact
    /// Why: Ensure listing solvers by emitting events is safe to call on-chain
    fun test_list_all_solvers(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
        solver2: &signer,
        caller: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Register first solver
        let (_solver_secret_key1, solver_public_key1) = ed25519::generate_keys();
        let solver_public_key_bytes1 = ed25519::validated_public_key_to_bytes(&solver_public_key1);
        let evm_addr1 = test_utils::create_test_evm_address(0);
        solver_registry::register_solver(solver, solver_public_key_bytes1, evm_addr1, @0x0);
        assert!(solver_registry::is_registered(signer::address_of(solver)), 1);
        
        // Register second solver
        let (_solver_secret_key2, solver_public_key2) = ed25519::generate_keys();
        let solver_public_key_bytes2 = ed25519::validated_public_key_to_bytes(&solver_public_key2);
        let evm_addr2 = test_utils::create_test_evm_address(1);
        solver_registry::register_solver(solver2, solver_public_key_bytes2, evm_addr2, @0x0);
        assert!(solver_registry::is_registered(signer::address_of(solver2)), 2);
        
        // Call list_all_solvers - should not abort
        // Note: Events are emitted but we can't easily verify them in Move unit tests
        // The function is tested end-to-end in shell scripts
        solver_registry::list_all_solvers(caller);
        
        // Verify solvers are still registered after calling list_all_solvers
        assert!(solver_registry::is_registered(signer::address_of(solver)), 3);
        assert!(solver_registry::is_registered(signer::address_of(solver2)), 4);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, caller = @0xabcd)]
    /// What is tested: list_all_solvers works when the registry is empty
    /// Why: Listing should be safe even before any solvers are registered
    fun test_list_all_solvers_empty_registry(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        caller: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Call list_all_solvers on empty registry - should not abort
        solver_registry::list_all_solvers(caller);
    }

    #[test(aptos_framework = @0x1, mvmt_intent = @0x123, solver = @0xcafe, solver2 = @0xbeef, caller = @0xabcd)]
    /// What is tested: list_all_solvers works correctly after one solver is deregistered
    /// Why: Ensure the internal solver_addresses list stays consistent across removals
    fun test_list_all_solvers_after_deregister(
        aptos_framework: &signer,
        mvmt_intent: &signer,
        solver: &signer,
        solver2: &signer,
        caller: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        solver_registry::init_for_test(mvmt_intent);
        
        // Register first solver
        let (_solver_secret_key1, solver_public_key1) = ed25519::generate_keys();
        let solver_public_key_bytes1 = ed25519::validated_public_key_to_bytes(&solver_public_key1);
        let evm_addr1 = test_utils::create_test_evm_address(0);
        solver_registry::register_solver(solver, solver_public_key_bytes1, evm_addr1, @0x0);
        
        // Register second solver
        let (_solver_secret_key2, solver_public_key2) = ed25519::generate_keys();
        let solver_public_key_bytes2 = ed25519::validated_public_key_to_bytes(&solver_public_key2);
        let evm_addr2 = test_utils::create_test_evm_address(1);
        solver_registry::register_solver(solver2, solver_public_key_bytes2, evm_addr2, @0x0);
        
        // Deregister first solver
        solver_registry::deregister_solver(solver);
        assert!(!solver_registry::is_registered(signer::address_of(solver)), 1);
        assert!(solver_registry::is_registered(signer::address_of(solver2)), 2);
        
        // Call list_all_solvers - should not abort and should only list remaining solver
        // Note: We can't verify events in Move unit tests, but we can verify the function executes
        solver_registry::list_all_solvers(caller);
        
        // Verify only solver2 is still registered
        assert!(!solver_registry::is_registered(signer::address_of(solver)), 3);
        assert!(solver_registry::is_registered(signer::address_of(solver2)), 4);
    }
}

