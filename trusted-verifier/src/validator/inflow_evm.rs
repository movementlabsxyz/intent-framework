//! Inflow EVM-specific validation functions
//!
//! This module contains EVM-specific handlers for inflow intent validation.

use crate::monitor::RequestIntentEvent;
use crate::validator::generic::ValidationResult;
use anyhow::{Context, Result};

/// Validates that an EVM escrow's reserved solver matches the registered solver's EVM address.
///
/// This function checks that the EVM escrow's reservedSolver address matches
/// the EVM address registered in the solver registry for the hub request intent's solver.
///
/// # Arguments
///
/// * `request_intent` - The request intent event from the hub chain (must have a solver)
/// * `escrow_reserved_solver` - The reserved solver EVM address from the escrow
/// * `hub_chain_rpc_url` - RPC URL of the hub chain (to query solver registry)
/// * `registry_address` - Address where the solver registry is deployed
///
/// # Returns
///
/// * `Ok(ValidationResult)` - Validation result with detailed information
/// * `Err(anyhow::Error)` - Validation failed due to error
pub async fn validate_evm_escrow_solver(
    request_intent: &RequestIntentEvent,
    escrow_reserved_solver: &str,
    hub_chain_rpc_url: &str,
    registry_address: &str,
) -> Result<ValidationResult> {
    // Check if request intent has a solver
    let request_intent_solver = match &request_intent.reserved_solver {
        Some(solver) => solver,
        None => {
            return Ok(ValidationResult {
                valid: false,
                message: "Hub request intent does not have a reserved solver".to_string(),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
    };

    // Query solver registry for EVM address
    let mvm_client = crate::mvm_client::MvmClient::new(hub_chain_rpc_url)?;
    let registered_evm_address = mvm_client
        .get_solver_evm_address(request_intent_solver, registry_address)
        .await
        .context("Failed to query solver EVM address from registry")?;

    let registered_evm_address = match registered_evm_address {
        Some(addr) => addr,
        None => {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Solver '{}' is not registered in the solver registry",
                    request_intent_solver
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
    };

    // Normalize addresses for comparison (lowercase, ensure 0x prefix)
    let escrow_solver_normalized = escrow_reserved_solver
        .strip_prefix("0x")
        .unwrap_or(escrow_reserved_solver)
        .to_lowercase();
    let registered_solver_normalized = registered_evm_address
        .strip_prefix("0x")
        .unwrap_or(&registered_evm_address)
        .to_lowercase();

    if escrow_solver_normalized != registered_solver_normalized {
        return Ok(ValidationResult {
            valid: false,
            message: format!(
                "EVM escrow reserved solver '{}' does not match registered solver EVM address '{}'",
                escrow_reserved_solver, registered_evm_address
            ),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    Ok(ValidationResult {
        valid: true,
        message: "EVM escrow solver validation successful".to_string(),
        timestamp: chrono::Utc::now().timestamp() as u64,
    })
}
