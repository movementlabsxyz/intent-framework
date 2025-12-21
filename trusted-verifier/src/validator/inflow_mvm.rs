//! Inflow MVM-specific validation functions
//!
//! This module contains MVM-specific handlers for inflow intent validation.

use crate::monitor::IntentEvent;
use crate::validator::generic::ValidationResult;
use anyhow::{Context, Result};

/// Validates that an MVM escrow's reserved solver matches the registered solver's connected chain MVM address.
///
/// This function checks that the MVM escrow's reservedSolver address matches
/// the connected chain MVM address registered in the solver registry for the hub intent's solver.
///
/// # Arguments
///
/// * `intent` - The intent event from the hub chain (must have a solver)
/// * `escrow_reserved_solver_addr` - The reserved solver MVM address from the escrow (on connected chain)
/// * `hub_chain_rpc_url` - RPC URL of the hub chain (to query solver registry)
/// * `solver_registry_addr` - Address where the solver registry is deployed
///
/// # Returns
///
/// * `Ok(ValidationResult)` - Validation result with detailed information
/// * `Err(anyhow::Error)` - Validation failed due to error
pub async fn validate_mvm_escrow_solver(
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

    // Query solver registry for connected chain MVM address
    let mvm_client = crate::mvm_client::MvmClient::new(hub_chain_rpc_url)?;
    let registered_mvm_addr = mvm_client
        .get_solver_connected_chain_mvm_address(intent_solver, solver_registry_addr)
        .await
        .context("Failed to query solver connected chain MVM address from registry")?;

    let registered_mvm_addr = match registered_mvm_addr {
        Some(addr) => addr,
        None => {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Solver '{}' is not registered in the solver registry or has no connected chain MVM address",
                    intent_solver
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
    };

    // Normalize addresses for comparison (remove 0x prefix, pad to 64 hex chars, lowercase)
    let escrow_solver_raw = escrow_reserved_solver_addr
        .strip_prefix("0x")
        .unwrap_or(escrow_reserved_solver_addr);
    let escrow_solver = format!("{:0>64}", escrow_solver_raw).to_lowercase();
    let registered_solver_raw = registered_mvm_addr
        .strip_prefix("0x")
        .unwrap_or(&registered_mvm_addr);
    let registered_solver = format!("{:0>64}", registered_solver_raw).to_lowercase();

    if escrow_solver != registered_solver {
        return Ok(ValidationResult {
            valid: false,
            message: format!(
                "MVM escrow reserved solver '{}' does not match registered solver connected chain MVM address '{}'",
                escrow_reserved_solver_addr, registered_mvm_addr
            ),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    Ok(ValidationResult {
        valid: true,
        message: "MVM escrow solver validation successful".to_string(),
        timestamp: chrono::Utc::now().timestamp() as u64,
    })
}
