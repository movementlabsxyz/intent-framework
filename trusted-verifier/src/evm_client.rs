//! EVM Client Module
//!
//! This module provides a client for communicating with EVM-compatible blockchain nodes
//! via their JSON-RPC API. It handles event polling and transaction verification.

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sha3::{Digest, Keccak256};
use std::time::Duration;

// ============================================================================
// API RESPONSE STRUCTURES
// ============================================================================

/// EVM JSON-RPC request wrapper
#[derive(Debug, Serialize)]
struct JsonRpcRequest {
    jsonrpc: String,
    method: String,
    params: Vec<serde_json::Value>,
    id: u64,
}

/// EVM JSON-RPC response wrapper
#[derive(Debug, Deserialize)]
struct JsonRpcResponse<T> {
    #[allow(dead_code)]
    jsonrpc: String,
    result: Option<T>,
    error: Option<JsonRpcError>,
    #[allow(dead_code)]
    id: u64,
}

#[derive(Debug, Deserialize)]
struct JsonRpcError {
    code: i32,
    message: String,
}

/// EVM event log entry
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct EvmLog {
    /// Address of the contract that emitted the event
    pub address: String,
    /// Array of topics (indexed event parameters)
    pub topics: Vec<String>,
    /// Event data (non-indexed parameters)
    pub data: String,
    /// Block number (JSON-RPC uses camelCase: blockNumber)
    #[serde(rename = "blockNumber")]
    pub block_number: String,
    /// Transaction hash (JSON-RPC uses camelCase: transactionHash)
    #[serde(rename = "transactionHash")]
    pub transaction_hash: String,
    /// Log index (JSON-RPC uses camelCase: logIndex)
    #[serde(rename = "logIndex")]
    pub log_index: String,
}

/// EscrowInitialized event data parsed from EVM logs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EscrowInitializedEvent {
    /// Intent ID (indexed, first topic)
    pub intent_id: String,
    /// Escrow contract address (indexed, second topic)
    pub escrow: String,
    /// Requester address (indexed, third topic) - the escrow creator
    pub requester: String,
    /// Token address (from data)
    pub token: String,
    /// Reserved solver address (from data)
    pub reserved_solver: String,
    /// Block number
    pub block_number: String,
    /// Transaction hash
    pub transaction_hash: String,
}

/// EVM transaction details from JSON-RPC
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct EvmTransaction {
    /// Transaction hash
    #[serde(rename = "hash")]
    pub hash: String,
    /// Block number (hex string)
    #[serde(rename = "blockNumber")]
    pub block_number: Option<String>,
    /// Transaction index in block (hex string)
    #[serde(rename = "transactionIndex")]
    pub transaction_index: Option<String>,
    /// From address (sender)
    #[serde(rename = "from")]
    pub from: String,
    /// To address (recipient/contract)
    #[serde(rename = "to")]
    pub to: Option<String>,
    /// Transaction data (calldata)
    pub input: String,
    /// Transaction value (in wei, hex string)
    pub value: String,
    /// Gas used (hex string)
    #[serde(rename = "gas")]
    pub gas: String,
    /// Gas price (hex string)
    #[serde(rename = "gasPrice")]
    pub gas_price: String,
    /// Transaction status (1 = success, 0 = failure, null = pending)
    pub status: Option<String>,
}

// ============================================================================
// EVM CLIENT IMPLEMENTATION
// ============================================================================

/// Client for communicating with EVM-compatible blockchain nodes via JSON-RPC
pub struct EvmClient {
    /// HTTP client for making requests
    client: Client,
    /// Base URL of the EVM node (e.g., "http://127.0.0.1:8545")
    base_url: String,
    /// Escrow contract address
    escrow_contract_address: String,
}

impl EvmClient {
    /// Creates a new EVM client for the given node URL
    ///
    /// # Arguments
    ///
    /// * `node_url` - Base URL of the EVM node (e.g., "http://127.0.0.1:8545")
    /// * `escrow_contract_address` - Address of the IntentEscrow contract
    ///
    /// # Returns
    ///
    /// * `Ok(EvmClient)` - Successfully created client
    /// * `Err(anyhow::Error)` - Failed to create client
    pub fn new(node_url: &str, escrow_contract_address: &str) -> Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .context("Failed to create HTTP client")?;

        Ok(Self {
            client,
            base_url: node_url.to_string(),
            escrow_contract_address: escrow_contract_address.to_string(),
        })
    }

    /// Queries EVM chain for EscrowInitialized events
    ///
    /// This method queries the EVM chain for EscrowInitialized events emitted by the
    /// IntentEscrow contract. It uses eth_getLogs to filter events by contract address
    /// and event signature.
    ///
    /// # Arguments
    ///
    /// * `from_block` - Starting block number (optional, "latest" if None)
    /// * `to_block` - Ending block number (optional, "latest" if None)
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<EscrowInitializedEvent>)` - List of EscrowInitialized events
    /// * `Err(anyhow::Error)` - Failed to query events
    pub async fn get_escrow_initialized_events(
        &self,
        from_block: Option<u64>,
        to_block: Option<u64>,
    ) -> Result<Vec<EscrowInitializedEvent>> {
        // EscrowInitialized event signature: keccak256("EscrowInitialized(uint256,address,address,address,address)")
        // Note: indexed parameters don't affect the signature, only the types matter
        // Event: EscrowInitialized(uint256 indexed intentId, address indexed escrow, address indexed requester, address token, address reservedSolver)
        // Signature string: "EscrowInitialized(uint256,address,address,address,address)"
        let signature_string = "EscrowInitialized(uint256,address,address,address,address)";
        let mut hasher = Keccak256::new();
        hasher.update(signature_string.as_bytes());
        let hash = hasher.finalize();
        let event_signature = format!("0x{}", hex::encode(hash));

        // Build filter: topics[0] = event signature, address = escrow contract
        let from_block_str = from_block
            .map(|n| format!("0x{:x}", n))
            .unwrap_or_else(|| "latest".to_string());
        let to_block_str = to_block
            .map(|n| format!("0x{:x}", n))
            .unwrap_or_else(|| "latest".to_string());

        let filter = serde_json::json!({
            "address": self.escrow_contract_address,
            "topics": [event_signature],
            "fromBlock": from_block_str,
            "toBlock": to_block_str,
        });

        let request = JsonRpcRequest {
            jsonrpc: "2.0".to_string(),
            method: "eth_getLogs".to_string(),
            params: vec![filter],
            id: 1,
        };

        let response: JsonRpcResponse<Vec<EvmLog>> = self
            .client
            .post(&self.base_url)
            .json(&request)
            .send()
            .await
            .with_context(|| format!("Failed to send eth_getLogs request to {}", self.base_url))?
            .json()
            .await
            .with_context(|| {
                format!(
                    "Failed to parse eth_getLogs response from {}",
                    self.base_url
                )
            })?;

        if let Some(error) = response.error {
            return Err(anyhow::anyhow!(
                "JSON-RPC error from {}: {} (code: {})",
                self.base_url,
                error.message,
                error.code
            ));
        }

        let logs = response.result.unwrap_or_default();
        let mut events = Vec::new();

        for log in logs {
            // EscrowInitialized(uint256 indexed intentId, address indexed escrow, address indexed requester, address token, address reservedSolver)
            // topics[0] = event signature
            // topics[1] = intentId (uint256, padded to 32 bytes)
            // topics[2] = escrow (address, padded to 32 bytes)
            // topics[3] = requester (address, padded to 32 bytes)
            // data = abi.encode(token, reservedSolver) - two addresses (64 bytes total)

            if log.topics.len() < 4 {
                continue; // Invalid event format
            }

            let intent_id = log.topics[1].clone();
            let escrow = format!("0x{}", &log.topics[2][26..]); // Extract address from padded topic
            let requester = format!("0x{}", &log.topics[3][26..]); // Extract address from padded topic

            // Parse data: two addresses (64 hex chars = 32 bytes each)
            let data = log.data.strip_prefix("0x").unwrap_or(&log.data);
            if data.len() < 128 {
                continue; // Invalid data length
            }

            let token = format!("0x{}", &data[24..64]); // Extract address from data (skip padding)
            let reserved_solver = format!("0x{}", &data[88..128]); // Extract second address

            events.push(EscrowInitializedEvent {
                intent_id,
                escrow,
                requester,
                token,
                reserved_solver,
                block_number: log.block_number,
                transaction_hash: log.transaction_hash,
            });
        }

        Ok(events)
    }

    /// Queries transaction details by hash using eth_getTransactionByHash
    ///
    /// # Arguments
    ///
    /// * `hash` - Transaction hash (with or without 0x prefix)
    ///
    /// # Returns
    ///
    /// * `Ok(EvmTransaction)` - Transaction information
    /// * `Err(anyhow::Error)` - Failed to query transaction
    pub async fn get_transaction(&self, hash: &str) -> Result<EvmTransaction> {
        // Normalize hash (ensure 0x prefix)
        let hash = if hash.starts_with("0x") {
            hash.to_string()
        } else {
            format!("0x{}", hash)
        };

        let request = JsonRpcRequest {
            jsonrpc: "2.0".to_string(),
            method: "eth_getTransactionByHash".to_string(),
            params: vec![serde_json::json!(hash)],
            id: 1,
        };

        let response: JsonRpcResponse<EvmTransaction> = self
            .client
            .post(&self.base_url)
            .json(&request)
            .send()
            .await
            .with_context(|| {
                format!(
                    "Failed to send eth_getTransactionByHash request to {}",
                    self.base_url
                )
            })?
            .json()
            .await
            .with_context(|| {
                format!(
                    "Failed to parse eth_getTransactionByHash response from {}",
                    self.base_url
                )
            })?;

        if let Some(error) = response.error {
            return Err(anyhow::anyhow!(
                "JSON-RPC error from {}: {} (code: {})",
                self.base_url,
                error.message,
                error.code
            ));
        }

        match response.result {
            Some(tx) => Ok(tx),
            None => Err(anyhow::anyhow!("Transaction not found: {}", hash)),
        }
    }

    /// Queries transaction receipt by hash using eth_getTransactionReceipt
    ///
    /// The receipt contains the transaction status, which is not available
    /// in eth_getTransactionByHash.
    ///
    /// # Arguments
    ///
    /// * `hash` - Transaction hash (with or without 0x prefix)
    ///
    /// # Returns
    ///
    /// * `Ok(Option<String>)` - Transaction status ("0x1" = success, "0x0" = failure, None = pending/not found)
    /// * `Err(anyhow::Error)` - Failed to query transaction receipt
    pub async fn get_transaction_receipt_status(&self, hash: &str) -> Result<Option<String>> {
        // Normalize hash (ensure 0x prefix)
        let hash = if hash.starts_with("0x") {
            hash.to_string()
        } else {
            format!("0x{}", hash)
        };

        let request = JsonRpcRequest {
            jsonrpc: "2.0".to_string(),
            method: "eth_getTransactionReceipt".to_string(),
            params: vec![serde_json::json!(hash)],
            id: 1,
        };

        #[derive(Debug, Deserialize)]
        struct TransactionReceipt {
            /// Transaction status (1 = success, 0 = failure)
            status: Option<String>,
        }

        let response: JsonRpcResponse<TransactionReceipt> = self
            .client
            .post(&self.base_url)
            .json(&request)
            .send()
            .await
            .with_context(|| {
                format!(
                    "Failed to send eth_getTransactionReceipt request to {}",
                    self.base_url
                )
            })?
            .json()
            .await
            .with_context(|| {
                format!(
                    "Failed to parse eth_getTransactionReceipt response from {}",
                    self.base_url
                )
            })?;

        if let Some(error) = response.error {
            return Err(anyhow::anyhow!(
                "JSON-RPC error from {}: {} (code: {})",
                self.base_url,
                error.message,
                error.code
            ));
        }

        Ok(response.result.and_then(|receipt| receipt.status))
    }

    /// Gets the current block number
    ///
    /// # Returns
    ///
    /// * `Ok(u64)` - Current block number
    /// * `Err(anyhow::Error)` - Failed to query block number
    pub async fn get_block_number(&self) -> Result<u64> {
        let request = JsonRpcRequest {
            jsonrpc: "2.0".to_string(),
            method: "eth_blockNumber".to_string(),
            params: vec![],
            id: 1,
        };

        let response: JsonRpcResponse<String> = self
            .client
            .post(&self.base_url)
            .json(&request)
            .send()
            .await
            .with_context(|| {
                format!(
                    "Failed to send eth_blockNumber request to {}",
                    self.base_url
                )
            })?
            .json()
            .await
            .with_context(|| {
                format!(
                    "Failed to parse eth_blockNumber response from {}",
                    self.base_url
                )
            })?;

        if let Some(error) = response.error {
            return Err(anyhow::anyhow!(
                "JSON-RPC error from {}: {} (code: {})",
                self.base_url,
                error.message,
                error.code
            ));
        }

        let block_number_hex = response
            .result
            .ok_or_else(|| anyhow::anyhow!("No result in eth_blockNumber response"))?;

        let block_number = u64::from_str_radix(
            block_number_hex
                .strip_prefix("0x")
                .unwrap_or(&block_number_hex),
            16,
        )
        .context("Failed to parse block number")?;

        Ok(block_number)
    }

    /// Returns the base URL of this client
    #[allow(dead_code)]
    pub fn base_url(&self) -> &str {
        &self.base_url
    }
}

