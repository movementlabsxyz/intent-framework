//! Outflow EVM-specific validation functions
//!
//! This module contains EVM-specific transaction parsing and parameter extraction
//! for outflow fulfillment validation.

use anyhow::{Result, Context};
use crate::evm_client::EvmTransaction;
use crate::validator::generic::FulfillmentTransactionParams;

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

