module aptos_intent::intent_as_escrow_entry {
    use std::signer;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::{Self as fungible_asset, FungibleAsset};
    use aptos_intent::intent_as_escrow::{Self, start_escrow_session, complete_escrow};
    use aptos_intent::intent::TradeIntent;
    use aptos_intent::fa_intent_with_oracle;
    use aptos_std::ed25519;

    // ============================================================================
    // GENERIC ESCROW FUNCTIONS
    // ============================================================================

    /// Creates an escrow with any fungible asset.
    /// Withdraws tokens from the caller's primary FA store and forwards them to create_escrow.
    /// 
    /// # Arguments
    /// - `user`: Signer creating the escrow
    /// - `source_metadata`: Metadata of the token type to lock in escrow
    /// - `amount`: Amount of tokens to lock in escrow
    /// - `verifier_public_key`: Public key of authorized verifier (32 bytes as hex)
    /// - `expiry_time`: Unix timestamp when escrow expires
    /// - `intent_id`: Intent ID from the hub chain (for cross-chain matching)
    /// - `reserved_solver`: Address of the solver who will receive funds when escrow is claimed
    public entry fun create_escrow_from_fa(
        user: &signer,
        source_metadata: Object<fungible_asset::Metadata>,
        amount: u64,
        verifier_public_key: vector<u8>, // 32 bytes
        expiry_time: u64,
        intent_id: address,
        reserved_solver: address,
    ) {
        use aptos_intent::intent_reservation;
        
        // Withdraw tokens as a FungibleAsset from the caller's primary FA store
        let fa: FungibleAsset = primary_fungible_store::withdraw(user, source_metadata, amount);

        // Build ed25519::UnvalidatedPublicKey correctly
        let oracle_pk = ed25519::new_unvalidated_public_key_from_bytes(verifier_public_key);

        // Create reservation for the specified solver
        // Escrows must always be reserved for a specific solver
        let reservation = intent_reservation::new_reservation(reserved_solver);

        // Call the general escrow creation function
        intent_as_escrow::create_escrow(user, fa, oracle_pk, expiry_time, intent_id, reservation);
    }

    /// CLI-friendly wrapper for completing escrow with any fungible asset.
    /// Handles start_escrow_session and complete_escrow in one transaction.
    /// 
    /// This function:
    /// 1. Starts the escrow session (gets locked assets)
    /// 2. Deposits locked assets to solver
    /// 3. Infers payment metadata from the escrowed asset
    /// 4. Withdraws payment from solver
    /// 5. Completes escrow with verifier approval signature
    /// 
    /// # Arguments
    /// - `solver`: Signer of the solver completing the escrow
    /// - `escrow_intent`: Object address of the escrow intent
    /// - `payment_amount`: Amount of tokens to provide as payment (should match escrow desired_amount, typically 1)
    /// - `verifier_approval`: Verifier's approval value (1 = approve, 0 = reject)
    /// - `verifier_signature_bytes`: Verifier's Ed25519 signature as bytes (base64 decoded)
    public entry fun complete_escrow_from_fa(
        solver: &signer,
        escrow_intent: Object<TradeIntent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>>,
        payment_amount: u64,
        verifier_approval: u64,
        verifier_signature_bytes: vector<u8>,
    ) {
        // Start escrow session to get the escrowed assets and create a session
        let (escrowed_asset, session) = start_escrow_session(solver, escrow_intent);
        
        // Infer payment metadata from the escrowed asset BEFORE depositing (FungibleAsset doesn't have copy)
        // Uses placeholder metadata matching source asset
        let payment_metadata = fungible_asset::asset_metadata(&escrowed_asset);
        
        // Deposit escrowed assets to solver (they get the locked tokens)
        primary_fungible_store::deposit(signer::address_of(solver), escrowed_asset);
        
        // Withdraw payment amount from solver
        let solver_payment = primary_fungible_store::withdraw(solver, payment_metadata, payment_amount);
        
        // Convert signature bytes to ed25519::Signature
        let verifier_signature = ed25519::new_signature_from_bytes(verifier_signature_bytes);
        
        // Complete the escrow with verifier approval
        complete_escrow(solver, session, solver_payment, verifier_approval, verifier_signature);
    }
}

