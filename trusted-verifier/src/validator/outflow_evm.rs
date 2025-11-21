//! Outflow EVM-specific validation functions
//!
//! This module contains EVM-specific transaction parsing and parameter extraction
//! for outflow fulfillment validation.

use crate::evm_client::EvmTransaction;
use crate::monitor::parse_amount_with_u64_limit;
use crate::validator::generic::{validate_address_format, FulfillmentTransactionParams};
use anyhow::{Context, Result};

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
        return Err(anyhow::anyhow!(
            "Insufficient calldata length for transfer with intent_id"
        ));
    }

    // Extract recipient address (bytes 4-35, skip selector)
    // EVM addresses are 20 bytes, but calldata pads them to 32 bytes (first 12 bytes should be zeros)
    let recipient_hex = &input[8..72]; // 32 bytes = 64 hex chars, starting after 4-byte selector

    // Validate calldata padding: first 12 bytes (24 hex chars) must be zeros
    let padding = &recipient_hex[0..24];
    if padding != "000000000000000000000000" {
        return Err(anyhow::anyhow!(
            "Invalid EVM address format in calldata: padding bytes are not zero. Expected 12 zero bytes, got: {}",
            padding
        ));
    }

    // Extract and validate the 20-byte address
    let address_part = &recipient_hex[24..64]; // Last 20 bytes (40 hex chars)
    let recipient = format!("0x{}", address_part);
    validate_address_format(&recipient, crate::monitor::ChainType::Evm)
        .context("Invalid EVM address format in calldata")?;

    // Extract amount (bytes 36-67)
    let amount_hex = &input[72..136]; // Next 32 bytes = 64 hex chars
    
    // Parse and validate amount using shared function (handles hex strings and u64::MAX validation)
    let amount = parse_amount_with_u64_limit(amount_hex, "EVM transfer amount")?;

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
        token_metadata: tx
            .to
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Transaction 'to' address (token contract) not found"))?
            .clone(),
    })
}
