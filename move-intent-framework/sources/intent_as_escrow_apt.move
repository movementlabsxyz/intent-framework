module aptos_intent::intent_as_escrow_apt {
    use std::signer;
    use std::option;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::FungibleAsset;
    use aptos_intent::intent_as_escrow::{Self, start_escrow_session, complete_escrow};
    use aptos_intent::intent::TradeIntent;
    use aptos_intent::fa_intent_with_oracle;
    use aptos_std::ed25519;

    // ============================================================================
    // APT-SPECIFIC ESCROW FUNCTIONS
    // ============================================================================

    /// CLI-friendly wrapper for creating escrow with APT tokens.
    /// Withdraws APT from the caller's primary FA store and forwards it to create_escrow.
    /// 
    /// # Arguments
    /// - `user`: Signer creating the escrow
    /// - `amount_octas`: Amount of APT to lock in escrow
    /// - `verifier_public_key`: Public key of authorized verifier (32 bytes as hex)
    /// - `expiry_time`: Unix timestamp when escrow expires
    /// - `intent_id`: Intent ID from the hub chain (for cross-chain matching)
    public entry fun create_escrow_from_apt(
        user: &signer,
        amount_octas: u64,
        verifier_public_key: vector<u8>, // 32 bytes
        expiry_time: u64,
        intent_id: address,
    ) {
        // Get APT's paired FA metadata (Object<Metadata>)
        let metadata_opt = coin::paired_metadata<aptos_coin::AptosCoin>();
        assert!(option::is_some(&metadata_opt), 9001);
        let metadata = option::destroy_some(metadata_opt);

        // Withdraw APT as a FungibleAsset from the caller's primary FA store
        let fa: FungibleAsset = primary_fungible_store::withdraw(user, metadata, amount_octas);

        // Build ed25519::UnvalidatedPublicKey correctly
        let oracle_pk = ed25519::new_unvalidated_public_key_from_bytes(verifier_public_key);

        // Call the general escrow creation function
        intent_as_escrow::create_escrow(user, fa, oracle_pk, expiry_time, intent_id);
    }

    /// CLI-friendly wrapper for completing escrow with APT tokens.
    /// Handles start_escrow_session and complete_escrow in one transaction.
    /// 
    /// This function:
    /// 1. Starts the escrow session (gets locked assets)
    /// 2. Deposits locked assets to solver
    /// 3. Withdraws payment from solver
    /// 4. Completes escrow with verifier approval signature
    /// 
    /// # Arguments
    /// - `solver`: Signer of the solver completing the escrow
    /// - `escrow_intent`: Object address of the escrow intent
    /// - `payment_amount_octas`: Amount of APT to provide as payment (should match escrow desired_amount, typically 1)
    /// - `verifier_approval`: Verifier's approval value (1 = approve, 0 = reject)
    /// - `verifier_signature_bytes`: Verifier's Ed25519 signature as bytes (base64 decoded)
    public entry fun complete_escrow_from_apt(
        solver: &signer,
        escrow_intent: Object<TradeIntent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>>,
        payment_amount_octas: u64,
        verifier_approval: u64,
        verifier_signature_bytes: vector<u8>,
    ) {
        // Start escrow session to get the escrowed assets and create a session
        let (escrowed_asset, session) = start_escrow_session(escrow_intent);
        
        // Deposit escrowed assets to solver (they get the locked tokens)
        primary_fungible_store::deposit(signer::address_of(solver), escrowed_asset);
        
        // Get APT metadata for payment
        let aptos_metadata_opt = coin::paired_metadata<aptos_coin::AptosCoin>();
        assert!(option::is_some(&aptos_metadata_opt), 9001);
        let aptos_metadata = option::destroy_some(aptos_metadata_opt);
        
        // Withdraw payment amount from solver
        let solver_payment = primary_fungible_store::withdraw(solver, aptos_metadata, payment_amount_octas);
        
        // Convert signature bytes to ed25519::Signature
        let verifier_signature = ed25519::new_signature_from_bytes(verifier_signature_bytes);
        
        // Complete the escrow with verifier approval
        complete_escrow(session, solver_payment, verifier_approval, verifier_signature);
    }
}

