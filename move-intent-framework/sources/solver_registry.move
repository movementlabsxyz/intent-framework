/// Module: mvmt_intent::solver_registry
/// 
/// Manages permissionless solver registration.
/// Stores solver's Ed25519 public key for signature validation and EVM address for escrow creation.

module mvmt_intent::solver_registry {
    use std::signer;
    use std::vector;
    use std::option;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_std::ed25519;

    // ==================== Error Codes ====================
    
    const E_NOT_INITIALIZED: u64 = 1;
    const E_ALREADY_INITIALIZED: u64 = 2;
    const E_SOLVER_NOT_FOUND: u64 = 3;
    const E_INVALID_PUBLIC_KEY: u64 = 4;
    const E_INVALID_EVM_ADDRESS: u64 = 5;
    const E_SOLVER_ALREADY_REGISTERED: u64 = 6;
    const E_PUBLIC_KEY_LENGTH_INVALID: u64 = 7;
    const E_EVM_ADDRESS_LENGTH_INVALID: u64 = 8;
    
    // ==================== Constants ====================
    
    /// Ed25519 public key length in bytes
    const ED25519_PUBLIC_KEY_LENGTH: u64 = 32;
    
    /// EVM address length in bytes (20 bytes = 160 bits)
    const EVM_ADDRESS_LENGTH: u64 = 20;
    
    // ==================== Structs ====================
    
    /// Solver registration information
    struct SolverInfo has store, drop {
        solver_addr: address,
        public_key: vector<u8>,  // Ed25519 public key (32 bytes)
        evm_address: vector<u8>, // EVM address (20 bytes)
        registered_at: u64,
    }
    
    /// Global solver registry
    struct SolverRegistry has key {
        solvers: SimpleMap<address, SolverInfo>,
    }
    
    // ==================== Events ====================
    
    #[event]
    struct SolverRegistered has drop, store {
        solver: address,
        public_key: vector<u8>,
        evm_address: vector<u8>,
        timestamp: u64,
    }
    
    #[event]
    struct SolverUpdated has drop, store {
        solver: address,
        public_key: vector<u8>,
        evm_address: vector<u8>,
        timestamp: u64,
    }
    
    #[event]
    struct SolverDeregistered has drop, store {
        solver: address,
        timestamp: u64,
    }
    
    // ==================== Public Functions ====================
    
    /// Initialize the solver registry (called once)
    /// The registry is stored at @mvmt_intent (the module's address)
    /// This must be called by the account that deployed the module (which has address = @mvmt_intent)
    public entry fun initialize(account: &signer) {
        let account_addr = signer::address_of(account);
        // Ensure the account deploying is the same as the module address
        assert!(account_addr == @mvmt_intent, E_NOT_INITIALIZED);
        assert!(!exists<SolverRegistry>(@mvmt_intent), E_ALREADY_INITIALIZED);
        
        move_to(account, SolverRegistry {
            solvers: simple_map::create(),
        });
    }
    
    /// Register as a new solver (permissionless)
    /// 
    /// # Arguments
    /// - `solver`: The solver signing the transaction
    /// - `public_key`: Ed25519 public key (32 bytes) for signature validation
    /// - `evm_address`: EVM address (20 bytes) for escrow creation on EVM chains
    public entry fun register_solver(
        solver: &signer,
        public_key: vector<u8>,
        evm_address: vector<u8>,
    ) acquires SolverRegistry {
        let solver_addr = signer::address_of(solver);
        let registry_addr = @mvmt_intent;
        
        assert!(exists<SolverRegistry>(registry_addr), E_NOT_INITIALIZED);
        
        let registry = borrow_global_mut<SolverRegistry>(registry_addr);
        
        // Check if solver already exists
        assert!(!simple_map::contains_key(&registry.solvers, &solver_addr), E_SOLVER_ALREADY_REGISTERED);
        
        // Validate public key length
        assert!(vector::length(&public_key) == ED25519_PUBLIC_KEY_LENGTH, E_PUBLIC_KEY_LENGTH_INVALID);
        
        // Validate EVM address length
        assert!(vector::length(&evm_address) == EVM_ADDRESS_LENGTH, E_EVM_ADDRESS_LENGTH_INVALID);
        
        // Validate public key is a valid Ed25519 public key
        let unvalidated_public_key = ed25519::new_unvalidated_public_key_from_bytes(public_key);
        let validated_public_key_opt = ed25519::public_key_validate(&unvalidated_public_key);
        assert!(option::is_some(&validated_public_key_opt), E_INVALID_PUBLIC_KEY);
        
        // Create solver info
        let solver_info = SolverInfo {
            solver_addr,
            public_key,
            evm_address,
            registered_at: timestamp::now_seconds(),
        };
        
        simple_map::add(&mut registry.solvers, solver_addr, solver_info);
        
        // Emit event
        let solver_data = simple_map::borrow(&registry.solvers, &solver_addr);
        event::emit(SolverRegistered {
            solver: solver_addr,
            public_key: solver_data.public_key,
            evm_address: solver_data.evm_address,
            timestamp: timestamp::now_seconds(),
        });
    }
    
    /// Update solver's public key and/or EVM address
    /// Only the solver themselves can update their registration
    public entry fun update_solver(
        solver: &signer,
        public_key: vector<u8>,
        evm_address: vector<u8>,
    ) acquires SolverRegistry {
        let solver_addr = signer::address_of(solver);
        let registry_addr = @mvmt_intent;
        
        assert!(exists<SolverRegistry>(registry_addr), E_NOT_INITIALIZED);
        
        let registry = borrow_global_mut<SolverRegistry>(registry_addr);
        
        // Check if solver exists
        assert!(simple_map::contains_key(&registry.solvers, &solver_addr), E_SOLVER_NOT_FOUND);
        
        // Validate public key length
        assert!(vector::length(&public_key) == ED25519_PUBLIC_KEY_LENGTH, E_PUBLIC_KEY_LENGTH_INVALID);
        
        // Validate EVM address length
        assert!(vector::length(&evm_address) == EVM_ADDRESS_LENGTH, E_EVM_ADDRESS_LENGTH_INVALID);
        
        // Validate public key is a valid Ed25519 public key
        let unvalidated_public_key = ed25519::new_unvalidated_public_key_from_bytes(public_key);
        let validated_public_key_opt = ed25519::public_key_validate(&unvalidated_public_key);
        assert!(option::is_some(&validated_public_key_opt), E_INVALID_PUBLIC_KEY);
        
        // Update solver info
        let solver_info = simple_map::borrow_mut(&mut registry.solvers, &solver_addr);
        solver_info.public_key = public_key;
        solver_info.evm_address = evm_address;
        
        // Emit event
        event::emit(SolverUpdated {
            solver: solver_addr,
            public_key: solver_info.public_key,
            evm_address: solver_info.evm_address,
            timestamp: timestamp::now_seconds(),
        });
    }
    
    /// Deregister solver from the registry
    /// Only the solver themselves can deregister
    public entry fun deregister_solver(
        solver: &signer,
    ) acquires SolverRegistry {
        let solver_addr = signer::address_of(solver);
        let registry_addr = @mvmt_intent;
        
        assert!(exists<SolverRegistry>(registry_addr), E_NOT_INITIALIZED);
        
        let registry = borrow_global_mut<SolverRegistry>(registry_addr);
        
        // Check if solver exists
        assert!(simple_map::contains_key(&registry.solvers, &solver_addr), E_SOLVER_NOT_FOUND);
        
        // Remove solver from registry
        simple_map::remove(&mut registry.solvers, &solver_addr);
        
        // Emit event
        event::emit(SolverDeregistered {
            solver: solver_addr,
            timestamp: timestamp::now_seconds(),
        });
    }
    
    // ==================== View Functions ====================
    
    /// Check if a solver is registered
    public fun is_registered(solver_addr: address): bool acquires SolverRegistry {
        if (!exists<SolverRegistry>(@mvmt_intent)) {
            return false
        };
        let registry = borrow_global<SolverRegistry>(@mvmt_intent);
        simple_map::contains_key(&registry.solvers, &solver_addr)
    }
    
    /// Get solver's Ed25519 public key
    /// Returns empty vector if solver is not registered
    public fun get_public_key(solver_addr: address): vector<u8> acquires SolverRegistry {
        if (!exists<SolverRegistry>(@mvmt_intent)) {
            return vector::empty()
        };
        let registry = borrow_global<SolverRegistry>(@mvmt_intent);
        if (!simple_map::contains_key(&registry.solvers, &solver_addr)) {
            return vector::empty()
        };
        let solver_info = simple_map::borrow(&registry.solvers, &solver_addr);
        solver_info.public_key
    }
    
    /// Get solver's EVM address
    /// Returns empty vector if solver is not registered
    public fun get_evm_address(solver_addr: address): vector<u8> acquires SolverRegistry {
        if (!exists<SolverRegistry>(@mvmt_intent)) {
            return vector::empty()
        };
        let registry = borrow_global<SolverRegistry>(@mvmt_intent);
        if (!simple_map::contains_key(&registry.solvers, &solver_addr)) {
            return vector::empty()
        };
        let solver_info = simple_map::borrow(&registry.solvers, &solver_addr);
        solver_info.evm_address
    }
    
    /// Get solver's public key as UnvalidatedPublicKey for signature verification
    /// Returns None if solver is not registered or public key is invalid
    public fun get_public_key_unvalidated(solver_addr: address): option::Option<ed25519::UnvalidatedPublicKey> acquires SolverRegistry {
        let public_key_bytes = get_public_key(solver_addr);
        if (vector::is_empty(&public_key_bytes)) {
            return option::none()
        };
        option::some(ed25519::new_unvalidated_public_key_from_bytes(public_key_bytes))
    }
    
    /// Get solver registration timestamp
    public fun get_registered_at(solver_addr: address): (bool, u64) acquires SolverRegistry {
        if (!exists<SolverRegistry>(@mvmt_intent)) {
            return (false, 0)
        };
        let registry = borrow_global<SolverRegistry>(@mvmt_intent);
        if (!simple_map::contains_key(&registry.solvers, &solver_addr)) {
            return (false, 0)
        };
        let solver_info = simple_map::borrow(&registry.solvers, &solver_addr);
        (true, solver_info.registered_at)
    }
    
    /// Get all solver information
    /// Returns (is_registered, public_key, evm_address, registered_at)
    public fun get_solver_info(solver_addr: address): (bool, vector<u8>, vector<u8>, u64) acquires SolverRegistry {
        if (!exists<SolverRegistry>(@mvmt_intent)) {
            return (false, vector::empty(), vector::empty(), 0)
        };
        let registry = borrow_global<SolverRegistry>(@mvmt_intent);
        if (!simple_map::contains_key(&registry.solvers, &solver_addr)) {
            return (false, vector::empty(), vector::empty(), 0)
        };
        let solver_info = simple_map::borrow(&registry.solvers, &solver_addr);
        (true, solver_info.public_key, solver_info.evm_address, solver_info.registered_at)
    }
    
    #[test_only]
    public fun init_for_test(account: &signer) {
        // In tests, initialize at the account's address (which should be @mvmt_intent)
        initialize(account);
    }
}

