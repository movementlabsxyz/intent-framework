//! Outflow Move VM-specific validation functions
//!
//! This module contains Move VM-specific transaction parsing and parameter extraction
//! for outflow fulfillment validation.

use anyhow::{Result, Context};
use crate::mvm_client::MvmTransaction;
use crate::validator::generic::FulfillmentTransactionParams;

/// Extracts intent_id and transaction parameters from a Move VM transaction
/// 
/// This function parses the transaction payload to extract parameters from
/// `utils::transfer_with_intent_id()` function calls.
/// 
/// # Arguments
/// 
/// * `tx` - The Move VM transaction information
/// 
/// # Returns
/// 
/// * `Ok(FulfillmentTransactionParams)` - Extracted parameters
/// * `Err(anyhow::Error)` - Failed to extract parameters
pub fn extract_mvm_fulfillment_params(tx: &MvmTransaction) -> Result<FulfillmentTransactionParams> {
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
    
    // Metadata is Object<Metadata> which is serialized as {"inner": "0x..."} in Aptos
    let metadata = if let Some(metadata_obj) = args[1].as_object() {
        // Extract inner address from Object<Metadata>
        metadata_obj.get("inner")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow::anyhow!("Invalid metadata: missing 'inner' field"))?
            .to_string()
    } else if let Some(metadata_str) = args[1].as_str() {
        // Fallback: if it's already a string, use it directly
        metadata_str.to_string()
    } else {
        return Err(anyhow::anyhow!("Invalid metadata: expected object with 'inner' field or string"));
    };
    
    // Aptos may serialize u64 values as either JSON numbers or hex strings
    // When passed as decimal to aptos CLI (u64:100000000), it's serialized as a JSON number
    // When passed as hex string, it's serialized as a hex string
    let amount = if let Some(amount_num) = args[2].as_u64() {
        amount_num
    } else if let Some(amount_str) = args[2].as_str() {
        // Try parsing as hex string
        u64::from_str_radix(
            amount_str.strip_prefix("0x").unwrap_or(amount_str),
            16,
        )
        .context("Failed to parse amount from hex string")?
    } else {
        return Err(anyhow::anyhow!("Invalid amount: expected number or hex string"));
    };
    
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

