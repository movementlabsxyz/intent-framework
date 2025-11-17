//! Aptos-specific API handlers
//!
//! This module contains Aptos-specific transaction querying and parameter extraction
//! for fulfillment validation.

use anyhow::Result;
use crate::validator::{CrossChainValidator, FulfillmentTransactionParams};

/// Queries an Aptos transaction and extracts fulfillment parameters.
/// 
/// This function handles the Aptos-specific logic for:
/// 1. Creating an Aptos client from configuration
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
pub async fn query_aptos_fulfillment_transaction(
    transaction_hash: &str,
    validator: &CrossChainValidator,
) -> Result<(FulfillmentTransactionParams, bool), String> {
    use crate::aptos_client::AptosClient;
    use crate::validator::extract_aptos_fulfillment_params;
    
    // Get Aptos client from config
    let aptos_config = validator.config().connected_chain_apt.as_ref()
        .ok_or_else(|| "Aptos chain not configured".to_string())?;
    
    let aptos_client = AptosClient::new(&aptos_config.rpc_url)
        .map_err(|e| format!("Failed to create Aptos client: {}", e))?;
    
    let tx = aptos_client.get_transaction(transaction_hash).await
        .map_err(|e| format!("Failed to query transaction: {}", e))?;
    
    let params = extract_aptos_fulfillment_params(&tx)
        .map_err(|e| format!("Failed to extract parameters: {}", e))?;
    
    Ok((params, tx.success))
}

