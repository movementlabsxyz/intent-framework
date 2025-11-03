module aptos_intent::fa_intent_cross_chain {
    use std::signer;
    use std::option;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self as object, Object};
    use aptos_framework::fungible_asset::{FungibleAsset, Metadata};
    use aptos_intent::fa_intent::{
        Self,
        FungibleStoreManager,
        FungibleAssetLimitOrder,
    };
    use aptos_intent::intent::{Self as intent, TradeIntent};

    // ============================================================================
    // GENERIC CROSS-CHAIN INTENT FUNCTIONS
    // ============================================================================

    /// Creates a cross-chain request intent that requests tokens without locking any tokens.
    /// The tokens are locked in an escrow on a different chain.
    ///
    /// # Arguments
    /// - `account`: Signer creating the intent
    /// - `source_metadata`: Metadata of the token type being offered (locked on another chain)
    /// - `desired_metadata`: Metadata of the desired token type
    /// - `desired_amount`: Amount of desired tokens
    /// - `expiry_time`: Unix timestamp when intent expires
    /// - `intent_id`: Intent ID for cross-chain linking
    /// 
    /// # Note
    /// This intent is special: it has 0 tokens locked because tokens are in escrow elsewhere.
    /// This function accepts any fungible asset metadata, enabling cross-chain swaps with any FA pair.
    public fun create_cross_chain_request_intent(
        account: &signer,
        source_metadata: Object<Metadata>,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        intent_id: address,
    ): address {
        // Withdraw 0 tokens of source type (no tokens locked, just requesting for cross-chain swap)
        let fa: FungibleAsset = primary_fungible_store::withdraw(account, source_metadata, 0);
        
        let intent_obj = fa_intent::create_fa_to_fa_intent(
            fa,
            desired_metadata,
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
    
    /// Entry function wrapper for CLI convenience.
    /// Accepts metadata objects and intent_id for cross-chain linking.
    public entry fun create_cross_chain_request_intent_entry(
        account: &signer,
        source_metadata: Object<Metadata>,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        intent_id: address,
    ) {
        // Create cross-chain request intent with reserved intent_id
        create_cross_chain_request_intent(account, source_metadata, desired_metadata, desired_amount, expiry_time, intent_id);
    }

    /// Entry function for solver to fulfill a cross-chain request intent.
    /// 
    /// This function:
    /// 1. Starts the session (unlocks 0 tokens since cross-chain intent has tokens locked on different chain)
    /// 2. Infers desired token metadata from the intent
    /// 3. Provides the desired tokens to the intent creator
    /// 4. Finishes the session to complete the intent
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
        
        // Deposit the unlocked tokens (which are 0 for cross-chain intents)
        primary_fungible_store::deposit(solver_address, unlocked_fa);
        
        // 2. Infer desired metadata from the intent's stored argument
        let argument = intent::get_argument(&session);
        let desired_metadata = fa_intent::get_desired_metadata(argument);
        
        // 3. Withdraw the desired tokens from solver's account
        let payment_fa = primary_fungible_store::withdraw(solver, desired_metadata, payment_amount);
        
        // 4. Finish the session by providing the payment tokens and emit fulfillment event
        fa_intent::finish_fa_receiving_session_with_event(session, payment_fa, intent_address, solver_address);
    }
}

