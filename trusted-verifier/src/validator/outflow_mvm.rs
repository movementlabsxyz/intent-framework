//! Outflow Move VM-specific validation functions
//!
//! This module contains Move VM-specific transaction parsing and parameter extraction
//! for outflow fulfillment validation.

use crate::mvm_client::MvmTransaction;
use crate::validator::generic::FulfillmentTransactionParams;
use anyhow::{Context, Result};

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
    let payload = tx
        .payload
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("Transaction payload not found"))?;

    // Check if this is a function call to utils::transfer_with_intent_id
    let function = payload
        .get("function")
        .and_then(|f| f.as_str())
        .ok_or_else(|| anyhow::anyhow!("Function not found in payload"))?;

    // Expected function format: "{module_address}::utils::transfer_with_intent_id"
    if !function.contains("transfer_with_intent_id") {
        return Err(anyhow::anyhow!(
            "Transaction is not a transfer_with_intent_id call"
        ));
    }

    // Extract function arguments
    let args = payload
        .get("arguments")
        .and_then(|a| a.as_array())
        .ok_or_else(|| anyhow::anyhow!("Function arguments not found"))?;

    // Function signature: transfer_with_intent_id(sender: &signer, recipient: address, metadata: Object<Metadata>, amount: u64, intent_id: address)
    // Arguments: [recipient, metadata, amount, intent_id] (sender is implicit from transaction)
    if args.len() < 4 {
        return Err(anyhow::anyhow!(
            "Insufficient arguments in transfer_with_intent_id call"
        ));
    }

    // Normalize Move VM address: strip 0x prefix, pad to 64 hex chars, add 0x back
    let recipient_raw = args[0]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("Invalid recipient address"))?;
    let recipient_no_prefix = recipient_raw.strip_prefix("0x").unwrap_or(recipient_raw);
    let recipient = format!("0x{:0>64}", recipient_no_prefix);

    // Metadata is Object<Metadata> which is serialized as {"inner": "0x..."} in Aptos
    let metadata = if let Some(metadata_obj) = args[1].as_object() {
        // Extract inner address from Object<Metadata>
        metadata_obj
            .get("inner")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow::anyhow!("Invalid metadata: missing 'inner' field"))?
            .to_string()
    } else if let Some(metadata_str) = args[1].as_str() {
        // Fallback: if it's already a string, use it directly
        metadata_str.to_string()
    } else {
        return Err(anyhow::anyhow!(
            "Invalid metadata: expected object with 'inner' field or string"
        ));
    };

    // Aptos may serialize u64 values as JSON numbers, decimal strings, or hex strings
    // When passed as decimal to aptos CLI (u64:100000000), it may be serialized as:
    // - JSON number: 100000000
    // - Decimal string: "100000000"
    // - Hex string: "0x5f5e100"
    // Parse as u64 (Move contract constraint)
    let amount = if let Some(amount_num) = args[2].as_u64() {
        amount_num
    } else if let Some(amount_str) = args[2].as_str() {
        // If string starts with "0x", parse as hex
        if amount_str.starts_with("0x") {
            u64::from_str_radix(&amount_str[2..], 16)
                .context("Failed to parse amount from hex string")?
        } else {
            // Parse as decimal string
            amount_str
                .parse::<u64>()
                .context("Failed to parse amount from decimal string")?
        }
    } else {
        return Err(anyhow::anyhow!("Invalid amount: expected number or string"));
    };

    // Normalize Move VM address: strip 0x prefix, pad to 64 hex chars, add 0x back
    let intent_id_raw = args[3]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("Invalid intent_id"))?;
    let intent_id_no_prefix = intent_id_raw.strip_prefix("0x").unwrap_or(intent_id_raw);
    let intent_id = format!("0x{:0>64}", intent_id_no_prefix);

    // Get sender from transaction and normalize Move VM address
    let solver_raw = tx
        .sender
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("Transaction sender not found"))?;
    let solver_no_prefix = solver_raw.strip_prefix("0x").unwrap_or(solver_raw);
    let solver = format!("0x{:0>64}", solver_no_prefix);

    Ok(FulfillmentTransactionParams {
        intent_id,
        recipient_addr: recipient,
        amount,
        solver_addr: solver,
        token_metadata: metadata,
    })
}
