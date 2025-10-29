module aptos_intent::fa_intent_apt {
    use std::signer;
    use std::option;
    use aptos_framework::coin;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self as object, Object};
    use aptos_framework::fungible_asset::FungibleAsset;
    use aptos_intent::fa_intent::{
        Self,
        FungibleStoreManager,
        FungibleAssetLimitOrder,
    };
    use aptos_intent::intent::TradeIntent;

    // ============================================================================
    // APT-SPECIFIC CROSS-CHAIN INTENT FUNCTIONS
    // ============================================================================

    /// CLI-friendly wrapper for creating a cross-chain request intent with APT tokens.
    /// This creates an intent that requests tokens without locking any tokens.
    /// The tokens are locked in an escrow on a different chain.
    ///
    /// # Arguments
    /// - `account`: Signer creating the intent
    /// - `desired_amount`: Amount of desired tokens
    /// - `expiry_time`: Unix timestamp when intent expires
    /// - `intent_id`: Intent ID for cross-chain linking
    /// 
    /// # Note
    /// This function is APT-specific for CLI convenience. For general fungible assets,
    /// use create_fa_to_fa_intent_entry with proper metadata objects.
    /// This intent is special: it has 0 tokens locked because tokens are in escrow elsewhere.
    public fun create_cross_chain_request_intent(
        account: &signer,
        desired_amount: u64,
        expiry_time: u64,
        intent_id: address,
    ): address {
        // Get APT metadata
        let metadata_opt = coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        assert!(option::is_some(&metadata_opt), 9001);
        let metadata = option::destroy_some(metadata_opt);
        
        // Withdraw 0 APT (no tokens locked, just requesting for cross-chain swap)
        let fa: FungibleAsset = primary_fungible_store::withdraw(account, metadata, 0);
        
        let intent_obj = fa_intent::create_fa_to_fa_intent(
            fa,
            metadata,
            desired_amount,
            expiry_time,
            signer::address_of(account),
            option::none(), // Unreserved
            false, // 🔒 CRITICAL: All parts of a cross-chain intent MUST be non-revocable (including the hub request intent)
                   // Ensures consistent safety guarantees for verifiers across chains
            option::some(intent_id), // Store the cross-chain intent_id for fulfillment event
        );
        
        // Event is already emitted by create_fa_to_fa_intent with the correct intent_id
        object::object_address(&intent_obj)
    }
    
    /// Entry function wrapper for CLI convenience
    /// Accepts intent_id for cross-chain linking
    public entry fun create_cross_chain_request_intent_entry(
        account: &signer,
        desired_amount: u64,
        expiry_time: u64,
        intent_id: address,
    ) {
        // Create cross-chain request intent with reserved intent_id
        create_cross_chain_request_intent(account, desired_amount, expiry_time, intent_id);
    }

    /// Entry function for solver to fulfill a cross-chain request intent with APT tokens.
    /// 
    /// This function:
    /// 1. Starts the session (unlocks 0 tokens since cross-chain intent has tokens locked on different chain)
    /// 2. Provides the desired tokens to the intent creator
    /// 3. Finishes the session to complete the intent
    /// 
    /// This is used for cross-chain swaps where tokens are locked in escrow on a different chain.
    /// 
    /// # Arguments
    /// - `solver`: Signer fulfilling the intent
    /// - `intent`: Object reference to the intent to fulfill
    /// - `payment_amount`: Amount of tokens to provide
    public entry fun fulfill_cross_chain_request_intent(
        solver: &signer,
        intent: Object<TradeIntent<FungibleStoreManager, FungibleAssetLimitOrder>>,
        payment_amount: u64,
    ) {
        let intent_address = object::object_address(&intent);
        let solver_address = signer::address_of(solver);
        
        // 1. Start the session (this unlocks 0 tokens, but creates the session)
        let (unlocked_fa, session) = fa_intent::start_fa_offering_session(solver, intent);
        
        // Deposit the unlocked tokens (which are 0 for regular intents)
        primary_fungible_store::deposit(solver_address, unlocked_fa);
        
        // 2. Withdraw the desired tokens from solver's account
        let aptos_metadata_opt = coin::paired_metadata<aptos_framework::aptos_coin::AptosCoin>();
        assert!(option::is_some(&aptos_metadata_opt), 9001);
        let aptos_metadata = option::destroy_some(aptos_metadata_opt);
        
        let payment_fa = primary_fungible_store::withdraw(solver, aptos_metadata, payment_amount);
        
        // 3. Finish the session by providing the payment tokens and emit fulfillment event
        fa_intent::finish_fa_receiving_session_with_event(session, payment_fa, intent_address, solver_address);
    }
}

