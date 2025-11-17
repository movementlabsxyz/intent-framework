//! EVM-specific validation functions
//!
//! This module contains EVM-specific transaction parsing, parameter extraction,
//! and escrow solver validation for fulfillment validation.

use anyhow::{Result, Context};
use crate::evm_client::EvmTransaction;
use crate::validator::{FulfillmentTransactionParams, ValidationResult};
use crate::monitor::RequestIntentEvent;

/// Extracts intent_id and transaction parameters from an EVM transaction
/// 
/// This function parses the transaction calldata to extract parameters from
/// ERC20 transfer() calls with appended intent_id.
/// 
/// # Arguments
/// 
/// * `tx` - The EVM transaction information
/// 
/// # Returns
/// 
/// * `Ok(FulfillmentTransactionParams)` - Extracted parameters
/// * `Err(anyhow::Error)` - Failed to extract parameters
pub fn extract_evm_fulfillment_params(tx: &EvmTransaction) -> Result<FulfillmentTransactionParams> {
    // ERC20 transfer() function selector: 0xa9059cbb
    let transfer_selector = "0xa9059cbb";
    
    // Check if calldata starts with transfer selector
    let input = tx.input.strip_prefix("0x").unwrap_or(&tx.input);
    if !input.starts_with(&transfer_selector[2..]) {
        return Err(anyhow::anyhow!("Transaction is not an ERC20 transfer call"));
    }

    // Calldata format: selector (4 bytes) + to (32 bytes) + amount (32 bytes) + intent_id (32 bytes)
    // Total: 4 + 32 + 32 + 32 = 100 bytes = 200 hex chars
    if input.len() < 200 {
        return Err(anyhow::anyhow!("Insufficient calldata length for transfer with intent_id"));
    }

    // Extract recipient address (bytes 4-35, skip selector)
    let recipient_hex = &input[8..72]; // 32 bytes = 64 hex chars, starting after 4-byte selector
    let recipient = format!("0x{}", recipient_hex);

    // Extract amount (bytes 36-67)
    let amount_hex = &input[72..136]; // Next 32 bytes = 64 hex chars
    let amount = u64::from_str_radix(amount_hex, 16)
        .context("Failed to parse amount from calldata")?;

    // Extract intent_id (bytes 68-99, last 32 bytes)
    let intent_id_hex = &input[136..200]; // Last 32 bytes = 64 hex chars
    let intent_id = format!("0x{}", intent_id_hex);

    // Get sender from transaction
    let solver = tx.from.clone();

    Ok(FulfillmentTransactionParams {
        intent_id,
        recipient,
        amount,
        solver,
        token_metadata: tx.to.as_ref()
            .ok_or_else(|| anyhow::anyhow!("Transaction 'to' address (token contract) not found"))?
            .clone(),
    })
}

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
    let aptos_client = crate::aptos_client::AptosClient::new(hub_chain_rpc_url)?;
    let registered_evm_address = aptos_client.get_solver_evm_address(request_intent_solver, registry_address)
        .await
        .context("Failed to query solver EVM address from registry")?;
    
    let registered_evm_address = match registered_evm_address {
        Some(addr) => addr,
        None => {
            return Ok(ValidationResult {
                valid: false,
                message: format!("Solver '{}' is not registered in the solver registry", request_intent_solver),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
    };
    
    // Normalize addresses for comparison (lowercase, ensure 0x prefix)
    let escrow_solver_normalized = escrow_reserved_solver.strip_prefix("0x")
        .unwrap_or(escrow_reserved_solver)
        .to_lowercase();
    let registered_solver_normalized = registered_evm_address.strip_prefix("0x")
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

