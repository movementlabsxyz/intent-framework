/// Simplified Escrow Module
/// 
/// This module provides a clean abstraction over the oracle-intent system,
/// allowing users to create escrows with simple yes/no verifier approval.
/// 
/// ⚠️ **IMPORTANT**: This module uses "verifier" terminology in its public API,
/// but internally calls oracle functions from fa_intent_with_oracle.move.
/// The verifier IS an oracle - we use oracle implementation to create verifier functionality.
/// 
/// The verifier acts as a trusted entity that approves or rejects escrow conditions.
/// Verifier provides approval_value: 1 = approve, 0 = reject
module aptos_intent::intent_as_escrow {
    use std::option::{Self as option};
    use std::signer;
    use std::error;
    use std::bcs;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::object::Object;
    use aptos_intent::fa_intent_with_oracle;
    use aptos_intent::intent::{TradeIntent, TradeSession};
    use aptos_std::ed25519;

    // ============================================================================
    // CONSTANTS
    // ============================================================================

    /// Oracle approval value: approve escrow release
    const ORACLE_APPROVE: u64 = 1;
    
    /// Oracle approval value: reject escrow release  
    const ORACLE_REJECT: u64 = 0;

    // ============================================================================
    // DATA TYPES
    // ============================================================================

    /// Simplified escrow configuration
    struct EscrowConfig has store, drop {
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        oracle_public_key: ed25519::UnvalidatedPublicKey,
        expiry_time: u64,
    }

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /// Creates a simple escrow with verifier approval requirement
    /// 
    /// # Arguments
    /// - `user`: Signer of the escrow creator
    /// - `source_asset`: Asset to be escrowed
    /// - `verifier_public_key`: Public key of authorized verifier
    /// - `expiry_time`: Unix timestamp when escrow expires
    /// 
    /// # Returns
    /// - `Object<TradeIntent<...>>`: Handle to the created escrow
    public fun create_escrow(
        user: &signer,
        source_asset: FungibleAsset,
        verifier_public_key: ed25519::UnvalidatedPublicKey,
        expiry_time: u64,
    ): Object<TradeIntent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>> {
        // Create verifier requirement: verifier must provide approval value >= 1 (approve)
        let requirement = fa_intent_with_oracle::new_oracle_signature_requirement(
            ORACLE_APPROVE,  // Verifier must provide 1 (approve) to release escrow
            verifier_public_key,
        );

        // Create the verifier-guarded intent with placeholder values
        // Note: desired_metadata and desired_amount are placeholders since actual logic is off-chain
        let placeholder_metadata = fungible_asset::asset_metadata(&source_asset); // Use same metadata as placeholder
        let placeholder_amount = 1; // Minimal placeholder amount
        
        fa_intent_with_oracle::create_fa_to_fa_intent_with_oracle_requirement(
            source_asset,
            placeholder_metadata,
            placeholder_amount,
            expiry_time,
            signer::address_of(user),
            requirement,
        )
    }

    /// Starts an escrow session for a solver to fulfill
    /// 
    /// # Arguments
    /// - `intent`: Handle to the escrow intent
    /// 
    /// # Returns
    /// - `FungibleAsset`: The escrowed asset that solver can claim
    /// - `TradeSession<...>`: Session for completing the escrow
    public fun start_escrow_session(
        intent: Object<TradeIntent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>>
    ): (FungibleAsset, TradeSession<fa_intent_with_oracle::OracleGuardedLimitOrder>) {
        fa_intent_with_oracle::start_fa_offering_session(intent)
    }

    /// Completes an escrow with verifier approval
    /// 
    /// # Arguments
    /// - `session`: Active escrow session
    /// - `solver_payment`: Asset provided by solver to fulfill escrow
    /// - `verifier_approval`: Verifier's approval decision (1 = approve, 0 = reject)
    /// - `verifier_signature`: Verifier's Ed25519 signature
    /// 
    /// # Aborts
    /// - If verifier approval is 0 (reject)
    /// - If verifier signature verification fails
    /// - If solver payment doesn't match escrow requirements
    public fun complete_escrow(
        session: TradeSession<fa_intent_with_oracle::OracleGuardedLimitOrder>,
        solver_payment: FungibleAsset,
        verifier_approval: u64,
        verifier_signature: ed25519::Signature,
    ) {
        // Verify verifier approved the escrow
        assert!(verifier_approval == ORACLE_APPROVE, error::invalid_argument(ORACLE_REJECT));

        // Create verifier witness with approval
        let witness = fa_intent_with_oracle::new_oracle_signature_witness(
            verifier_approval,
            verifier_signature,
        );

        // Complete the escrow
        fa_intent_with_oracle::finish_fa_receiving_session_with_oracle(
            session,
            solver_payment,
            option::some(witness),
        );
    }

    /// Revokes an escrow and returns assets to original depositor
    /// 
    /// # Arguments
    /// - `user`: Signer of the original escrow creator
    /// - `intent`: Handle to the escrow intent
    public fun revoke_escrow(
        user: &signer,
        intent: Object<TradeIntent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>>
    ) {
        fa_intent_with_oracle::revoke_fa_intent(user, intent);
    }

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    /// Creates verifier signature witness for approval
    /// 
    /// # Arguments
    /// - `verifier_secret_key`: Verifier's private key
    /// - `approve`: Whether to approve (true) or reject (false)
    /// 
    /// # Returns
    /// - `(u64, ed25519::Signature)`: Approval value and signature
    public fun create_oracle_approval(
        verifier_secret_key: &ed25519::SecretKey,
        approve: bool,
    ): (u64, ed25519::Signature) {
        let approval_value = if (approve) { ORACLE_APPROVE } else { ORACLE_REJECT };
        let signature = ed25519::sign_arbitrary_bytes(verifier_secret_key, bcs::to_bytes(&approval_value));
        (approval_value, signature)
    }

    /// Gets the approval constants for external use
    public fun get_oracle_approve(): u64 { ORACLE_APPROVE }
    public fun get_oracle_reject(): u64 { ORACLE_REJECT }
}
