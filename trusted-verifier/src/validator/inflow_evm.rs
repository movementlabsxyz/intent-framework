//! Inflow EVM-specific validation functions
//!
//! This module contains EVM-specific handlers for inflow intent validation.

use crate::monitor::IntentEvent;
use crate::validator::generic::ValidationResult;
use anyhow::{Context, Result};

/// Validates that an EVM escrow's reserved solver matches the registered solver's EVM address.
///
/// This function checks that the EVM escrow's reservedSolver address matches
/// the EVM address registered in the solver registry for the hub intent's solver.
///
/// # Arguments
///
/// * `intent` - The intent event from the hub chain (must have a solver)
/// * `escrow_reserved_solver_addr` - The reserved solver EVM address from the escrow
/// * `hub_chain_rpc_url` - RPC URL of the hub chain (to query solver registry)
/// * `solver_registry_addr` - Address where the solver registry is deployed
///
/// # Returns
///
/// * `Ok(ValidationResult)` - Validation result with detailed information
/// * `Err(anyhow::Error)` - Validation failed due to error
pub async fn validate_evm_escrow_solver(
    intent: &IntentEvent,
    escrow_reserved_solver_addr: &str,
    hub_chain_rpc_url: &str,
    solver_registry_addr: &str,
) -> Result<ValidationResult> {
    // Check if intent has a solver
    let intent_solver = match &intent.reserved_solver_addr {
        Some(solver) => solver,
        None => {
            return Ok(ValidationResult {
                valid: false,
                message: "Hub intent does not have a reserved solver".to_string(),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
    };

    // Query solver registry for EVM address
    let mvm_client = crate::mvm_client::MvmClient::new(hub_chain_rpc_url)?;
    let registered_evm_addr = mvm_client
        .get_solver_evm_address(intent_solver, solver_registry_addr)
        .await
        .context("Failed to query solver EVM address from registry")?;

    let registered_evm_addr = match registered_evm_addr {
        Some(addr) => addr,
        None => {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Solver '{}' is not registered in the solver registry",
                    intent_solver
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
    };

    // Normalize addresses for comparison (lowercase, ensure 0x prefix)
    let escrow_solver_normalized = escrow_reserved_solver_addr
        .strip_prefix("0x")
        .unwrap_or(escrow_reserved_solver_addr)
        .to_lowercase();
    let registered_solver_normalized = registered_evm_addr
        .strip_prefix("0x")
        .unwrap_or(&registered_evm_addr)
        .to_lowercase();

    if escrow_solver_normalized != registered_solver_normalized {
        return Ok(ValidationResult {
            valid: false,
            message: format!(
                "EVM escrow reserved solver '{}' does not match registered solver EVM address '{}'",
                escrow_reserved_solver_addr, registered_evm_addr
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
