//! Outflow Move VM-specific API handlers
//!
//! This module contains Move VM-specific transaction querying and parameter extraction
//! for outflow fulfillment validation on Move VM connected chains.

use crate::validator::{CrossChainValidator, FulfillmentTransactionParams};
use anyhow::Result;

/// Queries a Move VM transaction and extracts fulfillment parameters for outflow validation.
///
/// This function handles the Move VM-specific logic for:
/// 1. Creating a Move VM client from configuration
/// 2. Querying the transaction by hash
/// 3. Extracting fulfillment parameters from the transaction
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
pub async fn query_mvm_fulfillment_transaction(
    transaction_hash: &str,
    validator: &CrossChainValidator,
) -> Result<(FulfillmentTransactionParams, bool), String> {
    use crate::mvm_client::MvmClient;
    use crate::validator::extract_mvm_fulfillment_params;

    // Get Move VM client from config
    let mvm_config = validator
        .config()
        .connected_chain_mvm
        .as_ref()
        .ok_or_else(|| "Move VM chain not configured".to_string())?;

    let mvm_client = MvmClient::new(&mvm_config.rpc_url)
        .map_err(|e| format!("Failed to create Move VM client: {}", e))?;

    let tx = mvm_client
        .get_transaction(transaction_hash)
        .await
        .map_err(|e| format!("Failed to query transaction: {}", e))?;

    let params = extract_mvm_fulfillment_params(&tx)
        .map_err(|e| format!("Failed to extract parameters: {}", e))?;

    Ok((params, tx.success))
}
