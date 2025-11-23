module mvmt_intent::utils {
    use std::option;
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::object::{Self as object, Object};
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{FungibleAsset, Metadata};
    use aptos_framework::primary_fungible_store;
    use mvmt_intent::intent_reservation;

    #[event]
    struct APTMetadataAddressEvent has store, drop {
        metadata: address
    }

    #[event]
    struct IntentHashEvent has store, drop {
        hash: vector<u8>
    }

    /// Gets APT coin metadata address and returns it via event
    /// For use in E2E tests to get valid metadata addresses
    public entry fun get_apt_metadata_address(_account: &signer) {
        let metadata_opt = coin::paired_metadata<AptosCoin>();
        let metadata_ref = option::borrow(&metadata_opt);
        let metadata_addr = object::object_address(metadata_ref);

        event::emit(APTMetadataAddressEvent { metadata: metadata_addr });
    }

    /// Generates the hash of an IntentToSign structure for off-chain signing.
    ///
    /// This function constructs an IntentToSign struct and returns its BCS-encoded hash
    /// via event. The hash can then be signed off-chain using the solver's private key.
    ///
    /// # Arguments
    /// - `solver`: Signer of the solver account (must match solver_address)
    /// - `offered_metadata`: Metadata of the offered token type
    /// - `offered_amount`: Amount of offered tokens
    /// - `offered_chain_id`: Chain ID where offered tokens are located
    /// - `desired_metadata`: Metadata of the desired token type
    /// - `desired_amount`: Amount of desired tokens
    /// - `desired_chain_id`: Chain ID where desired tokens are located
    /// - `expiry_time`: Unix timestamp when intent expires
    /// - `requester`: Address of the intent requester
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
        offered_metadata: object::Object<Metadata>,
        offered_amount: u64,
        offered_chain_id: u64,
        desired_metadata: object::Object<Metadata>,
        desired_amount: u64,
        desired_chain_id: u64,
        expiry_time: u64,
        requester: address,
        solver_address: address
    ) {
        // Verify solver signer matches solver_address
        assert!(signer::address_of(solver) == solver_address, 1);

        // Create IntentToSign structure
        let intent_to_sign =
            intent_reservation::new_intent_to_sign(
                offered_metadata,
                offered_amount,
                offered_chain_id,
                desired_metadata,
                desired_amount,
                desired_chain_id,
                expiry_time,
                requester,
                solver_address
            );

        // Hash the intent (BCS encoding)
        let intent_hash = intent_reservation::hash_intent(intent_to_sign);

        // Emit hash via event for off-chain signing
        event::emit(IntentHashEvent { hash: intent_hash });
    }

    /// Transfers fungible assets to a recipient and includes intent_id in the transaction payload.
    ///
    /// This is a helper function for connected-chain transfers (outflow intents) that allows
    /// solvers to transfer tokens while including intent_id metadata. The intent_id is included
    /// as a parameter so the verifier can extract it from the transaction when querying by hash.
    ///
    /// # Arguments
    /// - `sender`: Signer of the solver account (must have tokens to transfer)
    /// - `recipient`: Address on the connected chain where tokens should be sent
    /// - `metadata`: Metadata object address for the token type
    /// - `amount`: Amount of tokens to transfer (base units)
    /// - `intent_id`: Intent ID that links this transaction to the hub intent (for verifier tracking)
    ///
    /// # Note
    /// This function is designed for outflow intents where solvers transfer tokens on connected chains.
    /// The intent_id parameter ensures the verifier can link the connected-chain transaction back
    /// to the hub intent when validating fulfillment.
    public entry fun transfer_with_intent_id(
        sender: &signer,
        recipient: address,
        metadata: Object<Metadata>,
        amount: u64,
        intent_id: address
    ) {
        // Withdraw tokens from sender's account
        let asset: FungibleAsset =
            primary_fungible_store::withdraw(sender, metadata, amount);

        // Deposit tokens to recipient address
        primary_fungible_store::deposit(recipient, asset);

        // Keep intent_id in payload so the verifier can read it from the transaction
        // The verifier queries the transaction by hash and extracts intent_id from function arguments
        let _intent_id = intent_id;
    }
}
