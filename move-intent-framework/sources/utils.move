module mvmt_intent::utils {
    use std::option;
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::object;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::Metadata;
    use mvmt_intent::intent_reservation;

    #[event]
    struct APTMetadataAddressEvent has store, drop {
        metadata: address,
    }

    #[event]
    struct IntentHashEvent has store, drop {
        hash: vector<u8>,
    }

    /// Gets APT coin metadata address and returns it via event
    /// For use in E2E tests to get valid metadata addresses
    public entry fun get_apt_metadata_address(
        _account: &signer,
    ) {
        let metadata_opt = coin::paired_metadata<AptosCoin>();
        let metadata_ref = option::borrow(&metadata_opt);
        let metadata_addr = object::object_address(metadata_ref);
        
        event::emit(APTMetadataAddressEvent {
            metadata: metadata_addr,
        });
    }

    /// Generates the hash of an IntentToSign structure for off-chain signing.
    /// 
    /// This function constructs an IntentToSign struct and returns its BCS-encoded hash
    /// via event. The hash can then be signed off-chain using the solver's private key.
    /// 
    /// # Arguments
    /// - `solver`: Signer of the solver account (must match solver_address)
    /// - `source_metadata`: Metadata of the source token type
    /// - `source_amount`: Amount of source tokens (0 for cross-chain request intents)
    /// - `desired_metadata`: Metadata of the desired token type
    /// - `desired_amount`: Amount of desired tokens
    /// - `expiry_time`: Unix timestamp when intent expires
    /// - `issuer`: Address of the intent issuer
    /// - `solver_address`: Address of the solver (must match signer)
    /// 
    /// # Note
    /// Move cannot extract private keys from `&signer`, so actual signing must be done
    /// off-chain. This function provides the hash that needs to be signed. For e2e tests,
    /// a helper script (Rust/Python) should:
    /// 1. Call this function to get the hash
    /// 2. Sign the hash with the solver's Ed25519 private key
    /// 3. Use the signature in create_cross_chain_request_intent_entry (solver must be registered in the registry)
    public entry fun get_intent_to_sign_hash(
        solver: &signer,
        source_metadata: object::Object<Metadata>,
        source_amount: u64,
        desired_metadata: object::Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        issuer: address,
        solver_address: address,
    ) {
        // Verify solver signer matches solver_address
        assert!(signer::address_of(solver) == solver_address, 1);
        
        // Create IntentToSign structure
        let intent_to_sign = intent_reservation::new_intent_to_sign(
            source_metadata,
            source_amount,
            desired_metadata,
            desired_amount,
            expiry_time,
            issuer,
            solver_address,
        );
        
        // Hash the intent (BCS encoding)
        let intent_hash = intent_reservation::hash_intent(intent_to_sign);
        
        // Emit hash via event for off-chain signing
        event::emit(IntentHashEvent {
            hash: intent_hash,
        });
    }
}

