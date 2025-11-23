//! Outflow EVM-specific API handlers
//!
//! This module contains EVM-specific transaction querying and parameter extraction
//! for outflow fulfillment validation on EVM connected chains.

use crate::validator::{CrossChainValidator, FulfillmentTransactionParams};
use anyhow::Result;

/// Queries an EVM transaction and extracts fulfillment parameters for outflow validation.
///
/// This function handles the EVM-specific logic for:
/// 1. Creating an EVM client from configuration
/// 2. Querying the transaction by hash
/// 3. Extracting fulfillment parameters from the transaction
/// 4. Determining transaction success status
///
/// # Arguments
///
/// * `transaction_hash` - The transaction hash to query
/// * `validator` - The cross-chain validator instance (for config access)
///
/// # Returns
///
/// * `Ok((FulfillmentTransactionParams, bool))` - Transaction parameters and success status
/// * `Err(String)` - Error message for API response
pub async fn query_evm_fulfillment_transaction(
    transaction_hash: &str,
    validator: &CrossChainValidator,
) -> Result<(FulfillmentTransactionParams, bool), String> {
    use crate::evm_client::EvmClient;
    use crate::validator::extract_evm_fulfillment_params;

    // Get EVM client from config
    let evm_config = validator
        .config()
        .connected_chain_evm
        .as_ref()
        .ok_or_else(|| "EVM chain not configured".to_string())?;

    let evm_client = EvmClient::new(&evm_config.rpc_url, &evm_config.escrow_contract_address)
        .map_err(|e| format!("Failed to create EVM client: {}", e))?;

    let tx = evm_client
        .get_transaction(transaction_hash)
        .await
        .map_err(|e| format!("Failed to query transaction: {}", e))?;

    let params = extract_evm_fulfillment_params(&tx)
        .map_err(|e| format!("Failed to extract parameters: {}", e))?;

    // Get transaction status from receipt (status is only available in receipt, not in transaction)
    let status = evm_client
        .get_transaction_receipt_status(transaction_hash)
        .await
        .map_err(|e| format!("Failed to query transaction receipt: {}", e))?;
    
    // Check transaction status (1 = success, 0 = failure, null = pending/not found)
    let success = status.as_ref().map(|s| s == "0x1").unwrap_or(false);

    Ok((params, success))
}
