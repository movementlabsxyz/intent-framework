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
/// 
/// ============================================================================
/// 🔒 CRITICAL SECURITY REQUIREMENT 🔒
/// ============================================================================
/// 
/// ⚠️  ESCROW INTENTS MUST ALWAYS BE CREATED AS NON-REVOCABLE ⚠️
/// 
/// This is a FUNDAMENTAL security requirement for any escrow system:
/// 
/// 1. Escrow funds MUST be locked and cannot be withdrawn by the user
/// 2. Funds can ONLY be released by verifier approval or rejection
/// 3. The `revocable` parameter MUST ALWAYS be set to `false` when creating escrow intents
/// 4. Any verifier implementation MUST verify that escrow intents are non-revocable
/// 5. This ensures verifiers can safely trigger actions elsewhere based on deposit events
/// 
/// FAILURE TO ENSURE NON-REVOCABLE ESCROW INTENTS COMPLETELY DEFEATS THE PURPOSE
/// OF AN ESCROW SYSTEM AND CREATES A CRITICAL SECURITY VULNERABILITY./// 
/// 
/// ============================================================================
module aptos_intent::intent_as_escrow {
    use std::option::{Self as option, Option};
    use std::signer;
    use std::error;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::object::Object;
    use aptos_intent::fa_intent_with_oracle;
    use aptos_intent::intent::{Self, TradeIntent, TradeSession};
    use aptos_intent::intent_reservation::{Self, IntentReserved};
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
    /// - `intent_id`: Intent ID from the hub chain (for cross-chain matching)
    /// - `reservation`: Required reservation specifying which solver can claim the escrow
    /// 
    /// # Returns
    /// - `Object<TradeIntent<...>>`: Handle to the created escrow
    /// 
    /// # Aborts
    /// - If reservation is None (escrows must always be reserved for a specific solver)
    public fun create_escrow(
        user: &signer,
        source_asset: FungibleAsset,
        verifier_public_key: ed25519::UnvalidatedPublicKey,
        expiry_time: u64,
        intent_id: address,
        reservation: IntentReserved,
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
            false, // 🔒 CRITICAL: escrow intents MUST be non-revocable for security!
            //      This ensures funds can ONLY be released by verifier approval/rejection
            //      Verifiers can safely trigger actions elsewhere based on deposit events
            intent_id,
            option::some(reservation), // Escrows must always be reserved for a specific solver
        )
    }

    /// Starts an escrow session for a solver to fulfill
    /// 
    /// # Arguments
    /// - `solver`: Signer of the solver attempting to claim the escrow
    /// - `intent`: Handle to the escrow intent
    /// 
    /// # Returns
    /// - `FungibleAsset`: The escrowed asset that solver can claim
    /// - `TradeSession<...>`: Session for completing the escrow
    ///
    /// # Aborts
    /// - If the escrow is reserved and the solver is not the authorized solver
    public fun start_escrow_session(
        solver: &signer,
        intent: Object<TradeIntent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>>
    ): (FungibleAsset, TradeSession<fa_intent_with_oracle::OracleGuardedLimitOrder>) {
        fa_intent_with_oracle::start_fa_offering_session(solver, intent)
    }

    /// Completes an escrow with verifier approval
    /// 
    /// # Arguments
    /// - `solver`: Signer of the solver completing the escrow
    /// - `session`: Active escrow session
    /// - `solver_payment`: Asset provided by solver to fulfill escrow
    /// - `verifier_approval`: Verifier's approval decision (1 = approve, 0 = reject)
    /// - `verifier_signature`: Verifier's Ed25519 signature
    /// 
    /// # Aborts
    /// - If verifier approval is 0 (reject)
    /// - If verifier signature verification fails
    /// - If solver payment doesn't match escrow requirements
    /// - If the escrow is reserved and the solver is not the authorized solver
    public fun complete_escrow(
        solver: &signer,
        session: TradeSession<fa_intent_with_oracle::OracleGuardedLimitOrder>,
        solver_payment: FungibleAsset,
        verifier_approval: u64,
        verifier_signature: ed25519::Signature,
    ) {
        // Verify solver is authorized if escrow is reserved
        let reservation = intent::get_reservation(&session);
        intent_reservation::ensure_solver_authorized(solver, reservation);
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

}
