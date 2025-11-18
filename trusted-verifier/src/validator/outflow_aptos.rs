//! Outflow Aptos-specific validation functions
//!
//! This module contains Aptos-specific transaction parsing and parameter extraction
//! for outflow fulfillment validation.

use anyhow::{Result, Context};
use crate::aptos_client::AptosTransaction;
use crate::validator::generic::FulfillmentTransactionParams;

/// Extracts intent_id and transaction parameters from an Aptos transaction
/// 
/// This function parses the transaction payload to extract parameters from
/// `utils::transfer_with_intent_id()` function calls.
/// 
/// # Arguments
/// 
/// * `tx` - The Aptos transaction information
/// 
/// # Returns
/// 
/// * `Ok(FulfillmentTransactionParams)` - Extracted parameters
/// * `Err(anyhow::Error)` - Failed to extract parameters
pub fn extract_aptos_fulfillment_params(tx: &AptosTransaction) -> Result<FulfillmentTransactionParams> {
    // Extract payload to get function call information
    let payload = tx.payload.as_ref()
        .ok_or_else(|| anyhow::anyhow!("Transaction payload not found"))?;

    // Check if this is a function call to utils::transfer_with_intent_id
    let function = payload.get("function")
        .and_then(|f| f.as_str())
        .ok_or_else(|| anyhow::anyhow!("Function not found in payload"))?;

    // Expected function format: "{module_address}::utils::transfer_with_intent_id"
    if !function.contains("transfer_with_intent_id") {
        return Err(anyhow::anyhow!("Transaction is not a transfer_with_intent_id call"));
    }

    // Extract function arguments
    let args = payload.get("arguments")
        .and_then(|a| a.as_array())
        .ok_or_else(|| anyhow::anyhow!("Function arguments not found"))?;

    // Function signature: transfer_with_intent_id(sender: &signer, recipient: address, metadata: Object<Metadata>, amount: u64, intent_id: address)
    // Arguments: [recipient, metadata, amount, intent_id] (sender is implicit from transaction)
    if args.len() < 4 {
        return Err(anyhow::anyhow!("Insufficient arguments in transfer_with_intent_id call"));
    }

    let recipient = args[0].as_str()
        .ok_or_else(|| anyhow::anyhow!("Invalid recipient address"))?
        .to_string();
    
    let metadata = args[1].as_str()
        .ok_or_else(|| anyhow::anyhow!("Invalid metadata"))?
        .to_string();
    
    let amount_str = args[2].as_str()
        .ok_or_else(|| anyhow::anyhow!("Invalid amount"))?;
    let amount = u64::from_str_radix(
        amount_str.strip_prefix("0x").unwrap_or(amount_str),
        16,
    )
    .context("Failed to parse amount")?;
    
    let intent_id = args[3].as_str()
        .ok_or_else(|| anyhow::anyhow!("Invalid intent_id"))?
        .to_string();

    // Get sender from transaction
    let solver = tx.sender.as_ref()
        .ok_or_else(|| anyhow::anyhow!("Transaction sender not found"))?
        .clone();

    Ok(FulfillmentTransactionParams {
        intent_id,
        recipient,
        amount,
        solver,
        token_metadata: metadata,
    })
}

