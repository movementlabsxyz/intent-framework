/// Tracks active intents for discovery by verifiers and solvers.
///
/// Security: Stores actual intent IDs (not just counts) to prevent malicious
/// cleanup. Only truly expired or fulfilled intents can be removed.
module mvmt_intent::intent_registry {
    // Friend modules that can register/unregister intents
    friend mvmt_intent::fa_intent_inflow;
    friend mvmt_intent::fa_intent_outflow;

    use std::error;
    use std::signer;
    use std::vector;

    use aptos_framework::timestamp;
    use aptos_std::simple_map::{Self, SimpleMap};

    // ==================== Error Codes ====================

    const E_NOT_INITIALIZED: u64 = 1;
    const E_ALREADY_INITIALIZED: u64 = 2;
    const E_INTENT_NOT_FOUND: u64 = 3;
    const E_INTENT_NOT_EXPIRED: u64 = 4;
    const E_INTENT_ALREADY_REGISTERED: u64 = 5;

    // ==================== Structs ====================

    /// Tracks which requester accounts have active intents.
    ///
    /// We store actual intent IDs (not just counts) so that:
    /// 1. Only truly expired/fulfilled intents can be removed
    /// 2. Double-cleanup is prevented
    /// 3. Malicious actors cannot decrement counts arbitrarily
    struct IntentRegistry has key {
        /// Maps intent_id -> (requester, expiry_time)
        /// Storing expiry_time here allows permissionless cleanup verification
        intent_info: SimpleMap<address, IntentInfo>,
        /// Maps requester -> list of their active intent_ids
        /// Used by get_active_requesters() to return unique requesters
        requester_intents: SimpleMap<address, vector<address>>,
    }

    /// Info stored per intent for cleanup verification
    struct IntentInfo has store, drop, copy {
        requester: address,
        expiry_time: u64,
    }

    // ==================== Initialization ====================

    /// Initialize the registry under the module address.
    /// Must be called once at deployment time by the module owner.
    public entry fun initialize(account: &signer) {
        let module_addr = signer::address_of(account);
        assert!(
            module_addr == @mvmt_intent,
            error::invalid_argument(E_NOT_INITIALIZED)
        );

        assert!(
            !exists<IntentRegistry>(module_addr),
            error::invalid_state(E_ALREADY_INITIALIZED)
        );

        move_to(
            account,
            IntentRegistry {
                intent_info: simple_map::new(),
                requester_intents: simple_map::new(),
            },
        );
    }

    // ==================== Friend Functions ====================

    /// Register a new intent in the registry.
    ///
    /// Called from intent creation functions (fa_intent_inflow, fa_intent_outflow).
    /// Stores the intent_id, requester, and expiry_time for cleanup verification.
    public(friend) fun register_intent(
        requester: address,
        intent_id: address,
        expiry_time: u64
    ) acquires IntentRegistry {
        assert!(
            exists<IntentRegistry>(@mvmt_intent),
            error::invalid_state(E_NOT_INITIALIZED)
        );
        let registry = borrow_global_mut<IntentRegistry>(@mvmt_intent);

        // Prevent duplicate registration
        assert!(
            !simple_map::contains_key(&registry.intent_info, &intent_id),
            error::already_exists(E_INTENT_ALREADY_REGISTERED)
        );

        // Add to intent_info map
        simple_map::add(
            &mut registry.intent_info,
            intent_id,
            IntentInfo { requester, expiry_time }
        );

        // Add to requester's intent list
        if (!simple_map::contains_key(&registry.requester_intents, &requester)) {
            simple_map::add(&mut registry.requester_intents, requester, vector::empty());
        };
        let intents = simple_map::borrow_mut(&mut registry.requester_intents, &requester);
        vector::push_back(intents, intent_id);
    }

    /// Unregister an intent from the registry.
    ///
    /// Called from intent fulfillment functions (fa_intent_inflow, fa_intent_outflow).
    /// Only friend modules can call this, enforced by public(friend).
    public(friend) fun unregister_intent(intent_id: address) acquires IntentRegistry {
        assert!(
            exists<IntentRegistry>(@mvmt_intent),
            error::invalid_state(E_NOT_INITIALIZED)
        );
        let registry = borrow_global_mut<IntentRegistry>(@mvmt_intent);

        // If intent not found, silently return (idempotent)
        if (!simple_map::contains_key(&registry.intent_info, &intent_id)) {
            return
        };

        // Get requester before removing
        let (_, info) = simple_map::remove(&mut registry.intent_info, &intent_id);
        let req = info.requester;

        // Remove from requester's list
        if (simple_map::contains_key(&registry.requester_intents, &req)) {
            let intents = simple_map::borrow_mut(&mut registry.requester_intents, &req);
            let (found, idx) = vector::index_of(intents, &intent_id);
            if (found) {
                vector::remove(intents, idx);
            };
            // If requester has no more intents, remove them from the map
            if (vector::is_empty(intents)) {
                simple_map::remove(&mut registry.requester_intents, &req);
            };
        };
    }

    /// Permissionless cleanup for expired intents.
    ///
    /// Anyone can call this, but it will only succeed if:
    /// 1. The intent exists in the registry
    /// 2. The intent's expiry_time has passed
    ///
    /// This prevents malicious actors from removing active intents.
    public entry fun cleanup_expired(_caller: &signer, intent_id: address) acquires IntentRegistry {
        assert!(
            exists<IntentRegistry>(@mvmt_intent),
            error::invalid_state(E_NOT_INITIALIZED)
        );
        let registry = borrow_global_mut<IntentRegistry>(@mvmt_intent);

        // Intent must exist
        assert!(
            simple_map::contains_key(&registry.intent_info, &intent_id),
            error::not_found(E_INTENT_NOT_FOUND)
        );

        // Check expiry
        let info = *simple_map::borrow(&registry.intent_info, &intent_id);
        let now = timestamp::now_seconds();
        assert!(
            now > info.expiry_time,
            error::permission_denied(E_INTENT_NOT_EXPIRED)
        );

        // Remove from intent_info
        let (_, removed_info) = simple_map::remove(&mut registry.intent_info, &intent_id);
        let req = removed_info.requester;

        // Remove from requester's list
        if (simple_map::contains_key(&registry.requester_intents, &req)) {
            let intents = simple_map::borrow_mut(&mut registry.requester_intents, &req);
            let (found, idx) = vector::index_of(intents, &intent_id);
            if (found) {
                vector::remove(intents, idx);
            };
            // If requester has no more intents, remove them from the map
            if (vector::is_empty(intents)) {
                simple_map::remove(&mut registry.requester_intents, &req);
            };
        };
    }

    // ==================== View Functions ====================

    #[view]
    /// Return list of all requester addresses with active intents.
    /// Used by the verifier/solver to know which accounts to poll for events.
    public fun get_active_requesters(): vector<address> acquires IntentRegistry {
        if (!exists<IntentRegistry>(@mvmt_intent)) {
            return vector::empty()
        };

        let registry = borrow_global<IntentRegistry>(@mvmt_intent);
        simple_map::keys(&registry.requester_intents)
    }

    #[view]
    /// Check if an intent is registered.
    public fun is_intent_registered(intent_id: address): bool acquires IntentRegistry {
        if (!exists<IntentRegistry>(@mvmt_intent)) {
            return false
        };
        let registry = borrow_global<IntentRegistry>(@mvmt_intent);
        simple_map::contains_key(&registry.intent_info, &intent_id)
    }

    #[view]
    /// Get the number of active intents for a requester.
    public fun get_intent_count(requester: address): u64 acquires IntentRegistry {
        if (!exists<IntentRegistry>(@mvmt_intent)) {
            return 0
        };
        let registry = borrow_global<IntentRegistry>(@mvmt_intent);
        if (!simple_map::contains_key(&registry.requester_intents, &requester)) {
            return 0
        };
        vector::length(simple_map::borrow(&registry.requester_intents, &requester))
    }

    // ============================================================================
    // TEST HELPERS
    // ============================================================================

    #[test_only]
    public fun init_for_test(account: &signer) {
        initialize(account);
    }

    #[test_only]
    public fun register_intent_for_test(
        requester: address,
        intent_id: address,
        expiry_time: u64
    ) acquires IntentRegistry {
        register_intent(requester, intent_id, expiry_time);
    }

    #[test_only]
    public fun unregister_intent_for_test(intent_id: address) acquires IntentRegistry {
        unregister_intent(intent_id);
    }
}
