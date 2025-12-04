//! Inflow-specific validation logic (chain-agnostic)
//!
//! This module handles validation logic for inflow intents.
//! Inflow intents have tokens locked on the connected chain (in escrow) and request tokens on the hub chain.

use anyhow::Result;
use tracing::info;

use super::generic::{CrossChainValidator, ValidationResult};
use super::inflow_evm;
use crate::monitor::{ChainType, EscrowEvent, IntentEvent};

/// Validates fulfillment of intent conditions on the connected chain.
///
/// This function performs comprehensive validation to ensure that:
/// 1. The intent has a connected_chain_id (required for escrow validation)
/// 2. The escrow's offered_amount matches the hub intent's offered_amount
/// 3. The escrow's offered_metadata matches the hub intent's offered_metadata
/// 4. The escrow's chain_id matches the hub intent's connected_chain_id
/// 5. The escrow's desired_amount is 0 (escrow only holds offered funds, requirement is in hub intent)
/// 6. The escrow's reserved_solver matches the hub intent's solver (with chain-specific validation)
///
/// # Arguments
///
/// * `validator` - The cross-chain validator instance
/// * `intent_event` - The intent event from the hub chain
/// * `escrow_event` - The escrow event from the connected chain
///
/// # Returns
///
/// * `Ok(ValidationResult)` - Validation result with detailed information
/// * `Err(anyhow::Error)` - Validation failed due to error
pub async fn validate_intent_fulfillment(
    validator: &CrossChainValidator,
    intent_event: &IntentEvent,
    escrow_event: &EscrowEvent,
) -> Result<ValidationResult> {
    info!(
        "Validating intent fulfillment for intent: {}, escrow: {}",
        intent_event.intent_id, escrow_event.escrow_id
    );

    // Validate that intent has connected_chain_id (required for escrow validation)
    if intent_event.connected_chain_id.is_none() {
        return Ok(ValidationResult {
            valid: false,
            message: "Request-intent must specify connected_chain_id for escrow validation"
                .to_string(),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    // Validate the escrow's offered_amount matches the specified offered_amount in the hub intent
    // Amounts are u64 (matching Move contract constraint)
    if escrow_event.offered_amount != intent_event.offered_amount {
        return Ok(ValidationResult {
            valid: false,
            message: format!(
                "Escrow offered amount {} does not match hub intent offered amount {}",
                escrow_event.offered_amount, intent_event.offered_amount
            ),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    // Validate the escrow's offered_metadata matches the specified offered_metadata in the hub intent
    if escrow_event.offered_metadata != intent_event.offered_metadata {
        return Ok(ValidationResult {
            valid: false,
            message: format!(
                "Escrow offered metadata '{}' does not match hub intent offered metadata '{}'",
                escrow_event.offered_metadata, intent_event.offered_metadata
            ),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    // Validate the escrow's chain_id matches the specified offered_chain_id in the hub intent
    // Note: offered_chain_id from Move event is stored as connected_chain_id in IntentEvent.
    // The escrow_event.chain_id is set by the verifier based on which monitor discovered it (from config),
    // so we can trust it for validation.
    if let Some(intent_offered_chain_id) = intent_event.connected_chain_id {
        if escrow_event.chain_id != intent_offered_chain_id {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Escrow chain_id {} does not match hub intent offered_chain_id {}. Escrow was discovered on chain {} but intent specifies chain {}",
                    escrow_event.chain_id, intent_offered_chain_id, escrow_event.chain_id, intent_offered_chain_id
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
    }

    // Validate that escrow's desired_amount is 0 (escrow only holds offered funds, requirement is in hub intent)
    // Amounts are u64 (matching Move contract constraint)
    if escrow_event.desired_amount != 0 {
        return Ok(ValidationResult {
            valid: false,
            message: format!(
                "Escrow desired amount must be 0, but got {}. Escrow only holds offered funds; the actual requirement is specified in the hub intent",
                escrow_event.desired_amount
            ),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    // Note: We don't validate escrow's desired_metadata because it's a placeholder.
    // The actual requirement is the hub intent's desired_metadata, which the solver
    // must fulfill on the hub chain before the verifier approves escrow release

    // Validate solver addresses match between escrow and intent
    // For Move VM escrows: Check if escrow's reserved_solver (Move VM address) matches hub intent's solver (Move VM address)
    // For EVM escrows: Check if escrow's reserved_solver (EVM address) matches registered solver's EVM address
    if let (Some(escrow_solver), Some(intent_solver)) = (
        &escrow_event.reserved_solver,
        &intent_event.reserved_solver,
    ) {
        // Determine chain type from the chain_type field set by the monitor
        let is_evm_escrow = escrow_event.chain_type == ChainType::Evm;

        if is_evm_escrow {
            // EVM escrow: Compare EVM addresses
            // The escrow_solver is an EVM address, intent_solver is a Move VM address
            // We need to query the solver registry to get the EVM address for intent_solver
            let hub_rpc_url = &validator.config.hub_chain.rpc_url;
            let registry_address = &validator.config.hub_chain.intent_module_address; // Registry is at module address

            let validation_result = inflow_evm::validate_evm_escrow_solver(
                intent_event,
                escrow_solver,
                hub_rpc_url,
                registry_address,
            )
            .await?;

            if !validation_result.valid {
                return Ok(validation_result);
            }
        } else {
            // Move VM escrow: Compare Move VM addresses directly
            if escrow_solver != intent_solver {
                return Ok(ValidationResult {
                    valid: false,
                    message: format!(
                        "Escrow reserved solver '{}' does not match hub intent solver '{}'",
                        escrow_solver, intent_solver
                    ),
                    timestamp: chrono::Utc::now().timestamp() as u64,
                });
            }
        }
    } else if escrow_event.reserved_solver.is_some()
        || intent_event.reserved_solver.is_some()
    {
        // One is reserved but the other is not - mismatch
        return Ok(ValidationResult {
            valid: false,
            message: format!(
                "Escrow and intent reservation mismatch: escrow reserved_solver={:?}, intent solver={:?}",
                escrow_event.reserved_solver, intent_event.reserved_solver
            ),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    // All validations passed
    Ok(ValidationResult {
        valid: true,
        message: "Request-intent fulfillment validation successful".to_string(),
        timestamp: chrono::Utc::now().timestamp() as u64,
    })
}
