//! Connected EVM Chain Client
//!
//! Client for interacting with connected EVM chains to query escrow events
//! and execute ERC20 transfers with intent_id metadata.

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sha3::{Digest, Keccak256};
use std::time::Duration;

use crate::config::EvmChainConfig;

/// EscrowInitialized event data parsed from EVM logs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EscrowInitializedEvent {
    /// Intent ID (indexed, first topic)
    pub intent_id: String,
    /// Escrow contract address (indexed, second topic)
    pub escrow: String,
    /// Requester address (indexed, third topic)
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
#[derive(Debug, Clone, Deserialize)]
struct EvmLog {
    /// Address of the contract that emitted the event
    #[allow(dead_code)]
    pub address: String,
    /// Array of topics (indexed event parameters)
    pub topics: Vec<String>,
    /// Event data (non-indexed parameters)
    pub data: String,
    /// Block number
    #[serde(rename = "blockNumber")]
    pub block_number: String,
    /// Transaction hash
    #[serde(rename = "transactionHash")]
    pub transaction_hash: String,
}

/// Client for interacting with a connected EVM chain
pub struct ConnectedEvmClient {
    /// HTTP client for JSON-RPC calls
    client: Client,
    /// Base RPC URL
    base_url: String,
    /// Escrow contract address
    escrow_contract_address: String,
    /// Chain ID (for future transaction signing)
    #[allow(dead_code)]
    chain_id: u64,
}

impl ConnectedEvmClient {
    /// Creates a new connected EVM chain client
    ///
    /// # Arguments
    ///
    /// * `config` - EVM chain configuration
    ///
    /// # Returns
    ///
    /// * `Ok(ConnectedEvmClient)` - Successfully created client
    /// * `Err(anyhow::Error)` - Failed to create client
    pub fn new(config: &EvmChainConfig) -> Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .context("Failed to create HTTP client")?;

        Ok(Self {
            client,
            base_url: config.rpc_url.clone(),
            escrow_contract_address: config.escrow_contract_address.clone(),
            chain_id: config.chain_id,
        })
    }

    /// Queries the connected chain for EscrowInitialized events
    ///
    /// Uses eth_getLogs to filter events by contract address and event signature.
    ///
    /// # Arguments
    ///
    /// * `from_block` - Starting block number (optional, "latest" if None)
    /// * `to_block` - Ending block number (optional, "latest" if None)
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<EscrowInitializedEvent>)` - List of escrow events
    /// * `Err(anyhow::Error)` - Failed to query events
    pub async fn get_escrow_events(
        &self,
        from_block: Option<u64>,
        to_block: Option<u64>,
    ) -> Result<Vec<EscrowInitializedEvent>> {
        // EscrowInitialized event signature: keccak256("EscrowInitialized(uint256,address,address,address,address)")
        // Event signature hash: first topic in logs
        let event_signature = "EscrowInitialized(uint256,address,address,address,address)";
        let mut hasher = Keccak256::new();
        hasher.update(event_signature.as_bytes());
        let event_topic = format!("0x{}", hex::encode(hasher.finalize()));

        // Build filter
        let mut filter = serde_json::json!({
            "address": self.escrow_contract_address,
            "topics": [event_topic]
        });

        if let Some(from) = from_block {
            filter["fromBlock"] = serde_json::json!(format!("0x{:x}", from));
        } else {
            filter["fromBlock"] = serde_json::json!("latest");
        }

        if let Some(to) = to_block {
            filter["toBlock"] = serde_json::json!(format!("0x{:x}", to));
        } else {
            filter["toBlock"] = serde_json::json!("latest");
        }

        // Call eth_getLogs
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
            .context("Failed to send eth_getLogs request")?
            .json()
            .await
            .context("Failed to parse eth_getLogs response")?;

        if let Some(error) = response.error {
            anyhow::bail!("JSON-RPC error: {} ({})", error.message, error.code);
        }

        let logs = response.result.unwrap_or_default();
        let mut events = Vec::new();

        for log in logs {
            // Topics: [event_signature, intent_id, escrow, requester]
            // Data: token (20 bytes) + reserved_solver (20 bytes) = 64 hex chars
            if log.topics.len() < 4 {
                continue; // Invalid event format
            }

            let intent_id = format!("0x{}", log.topics[1].strip_prefix("0x").unwrap_or(&log.topics[1]));
            let escrow = format!("0x{}", &log.topics[2][26..]); // Extract last 20 bytes (40 hex chars)
            let requester = format!("0x{}", &log.topics[3][26..]);

            // Parse data: token (32 bytes) + reserved_solver (32 bytes)
            let data = log.data.strip_prefix("0x").unwrap_or(&log.data);
            if data.len() < 128 {
                continue; // Invalid data length
            }

            let token = format!("0x{}", &data[24..64]); // Extract last 20 bytes from first 32-byte word
            let reserved_solver = format!("0x{}", &data[88..128]); // Extract last 20 bytes from second 32-byte word

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

    /// Executes an ERC20 transfer with intent_id appended in calldata
    ///
    /// The calldata format is: selector (4 bytes) + recipient (32 bytes) + amount (32 bytes) + intent_id (32 bytes).
    /// The ERC20 contract ignores the extra intent_id bytes, but they remain in the transaction
    /// data for verifier tracking.
    ///
    /// # Arguments
    ///
    /// * `token_address` - ERC20 token contract address
    /// * `recipient` - Recipient address
    /// * `amount` - Transfer amount (in base units, e.g., wei)
    /// * `intent_id` - Intent ID to append in calldata (32 bytes, hex format)
    /// * `private_key` - Private key for signing the transaction
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Transaction hash
    /// * `Err(anyhow::Error)` - Failed to execute transfer
    ///
    /// # Note
    ///
    /// This function requires signing the transaction. For now, this is a placeholder
    /// that returns an error. Full implementation would require an Ethereum signing library
    /// like `ethers` or `alloy`.
    pub async fn transfer_with_intent_id(
        &self,
        _token_address: &str,
        _recipient: &str,
        _amount: u128,
        _intent_id: &str,
        _private_key: &str,
    ) -> Result<String> {
        // TODO: Implement ERC20 transfer with intent_id using ethers-rs or alloy
        // For now, return an error indicating this needs to be implemented
        anyhow::bail!(
            "transfer_with_intent_id not yet implemented. Requires Ethereum signing library (ethers-rs or alloy)"
        )
    }
}

