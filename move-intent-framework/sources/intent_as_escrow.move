/// Simplified Escrow Module
///
/// This module provides a clean abstraction over the oracle-intent system,
/// allowing users to create escrows with simple yes/no verifier approval.
///
/// **IMPORTANT**: This module uses "verifier" terminology in its public API,
/// but internally calls oracle functions from fa_intent_with_oracle.move.
/// The verifier IS an oracle - we use oracle implementation to create verifier functionality.
///
/// The verifier acts as a trusted entity that approves or rejects escrow conditions.
/// Verifier provides approval_value: 1 = approve, 0 = reject
///
module mvmt_intent::intent_as_escrow {
    use std::option::{Self as option};
    use std::signer;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::object::Object;
    use mvmt_intent::fa_intent_with_oracle;
    use mvmt_intent::intent::{Self, Intent, Session};
    use mvmt_intent::intent_reservation::{Self, IntentReserved};
    use aptos_std::ed25519;

    // ============================================================================
    // DATA TYPES
    // ============================================================================

    /// Simplified escrow configuration
    struct EscrowConfig has store, drop {
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        oracle_public_key: ed25519::UnvalidatedPublicKey,
        expiry_time: u64
    }

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /// Creates a simple escrow with verifier approval requirement
    ///
    /// # Arguments
    /// - `requester_signer`: Signer of the escrow creator (requester who created the intent on hub chain)
    /// - `offered_asset`: Asset to be escrowed
    /// - `offered_chain_id`: Chain ID where the escrow is created (connected chain)
    /// - `verifier_public_key`: Public key of authorized verifier
    /// - `expiry_time`: Unix timestamp when escrow expires
    /// - `intent_id`: Intent ID from the hub chain (for cross-chain matching)
    /// - `reservation`: Required reservation specifying which solver can claim the escrow
    /// - `desired_chain_id`: Chain ID where desired tokens are located (hub chain for inflow intents)
    ///
    /// # Returns
    /// - `Object<Intent<...>>`: Handle to the created escrow
    ///
    /// # Aborts
    /// - If reservation is None (escrows must always be reserved for a specific solver)
    public fun create_escrow(
        requester_signer: &signer,
        offered_asset: FungibleAsset,
        offered_chain_id: u64,
        verifier_public_key: ed25519::UnvalidatedPublicKey,
        expiry_time: u64,
        intent_id: address,
        reservation: IntentReserved,
        desired_chain_id: u64
    ): Object<Intent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>> {
        // Create verifier requirement: signature itself is the approval, min_reported_value is 0
        // (the signature verification is what matters, not the reported_value)
        let requirement =
            fa_intent_with_oracle::new_oracle_signature_requirement(
                0, // min_reported_value: signature verification is what matters, this check always passes
                verifier_public_key
            );

        // Create the verifier-guarded intent with placeholder values
        // Note: desired_metadata and desired_amount are placeholders since actual logic is off-chain
        let placeholder_metadata = fungible_asset::asset_metadata(&offered_asset); // Use same metadata as placeholder
        let placeholder_amount = 0; // Placeholder (escrow validation is done off-chain by verifier)

        fa_intent_with_oracle::create_fa_to_fa_intent_with_oracle_requirement(
            offered_asset,
            offered_chain_id, // Chain ID where escrow is created (connected chain)
            placeholder_metadata,
            placeholder_amount, // desired_amount: use placeholder_amount (payment validation will check chain IDs)
            desired_chain_id, // Chain ID where desired tokens are located (hub chain for inflow)
            expiry_time,
            signer::address_of(requester_signer),
            requirement,
            false, // CRITICAL: escrow intents MUST be non-revocable for security!
            //      This ensures funds can ONLY be released by verifier approval/rejection
            //      Verifiers can safely trigger actions elsewhere based on deposit events
            intent_id,
            option::none(), // Not an outflow intent, so no requester address on connected chain
            option::some(reservation) // Escrows must always be reserved for a specific solver
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
    /// - `Session<...>`: Session for completing the escrow
    ///
    /// # Aborts
    /// - If the escrow is reserved and the solver is not the authorized solver
    public fun start_escrow_session(
        solver: &signer,
        intent: Object<Intent<fa_intent_with_oracle::FungibleStoreManager, fa_intent_with_oracle::OracleGuardedLimitOrder>>
    ): (FungibleAsset, Session<fa_intent_with_oracle::OracleGuardedLimitOrder>) {
        fa_intent_with_oracle::start_fa_offering_session(solver, intent)
    }

    /// Completes an escrow with verifier approval
    ///
    /// The verifier signs the intent_id - the signature itself is the approval.
    /// If the signature verifies correctly against the escrow's intent_id, the escrow is approved.
    ///
    /// # Arguments
    /// - `solver`: Signer of the solver completing the escrow
    /// - `session`: Active escrow session
    /// - `solver_payment`: Asset provided by solver to fulfill escrow
    /// - `verifier_signature`: Verifier's Ed25519 signature (signs the intent_id)
    ///
    /// # Aborts
    /// - If verifier signature verification fails (wrong intent_id or invalid signature)
    /// - If solver payment doesn't match escrow requirements
    /// - If the escrow is reserved and the solver is not the authorized solver
    public fun complete_escrow(
        solver: &signer,
        session: Session<fa_intent_with_oracle::OracleGuardedLimitOrder>,
        solver_payment: FungibleAsset,
        verifier_signature: ed25519::Signature
    ) {
        // Verify solver is authorized if escrow is reserved
        let reservation = intent::get_reservation(&session);
        intent_reservation::ensure_solver_authorized(solver, reservation);

        // Create verifier witness - signature itself is the approval, reported_value is just metadata
        // We use 0 as reported_value since min_reported_value is 0 (signature verification is what matters)
        let witness =
            fa_intent_with_oracle::new_oracle_signature_witness(
                0, // reported_value: signature verification is what matters, this is just metadata
                verifier_signature
            );

        // Complete the escrow
        fa_intent_with_oracle::finish_fa_receiving_session_with_oracle(
            session,
            solver_payment,
            option::some(witness)
        );
    }
}
