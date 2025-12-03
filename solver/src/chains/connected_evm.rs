//! Connected EVM Chain Client
//!
//! Client for interacting with connected EVM chains to query escrow events
//! and execute ERC20 transfers with intent_id metadata.

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sha3::{Digest, Keccak256};
use std::process::Command;
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
    /// Calls the Hardhat script `transfer-with-intent-id.js` via `npx hardhat run`,
    /// matching the approach used in E2E test scripts. The script uses Hardhat's signer[2]
    /// (Solver account) for signing the transaction.
    ///
    /// # Arguments
    ///
    /// * `token_address` - ERC20 token contract address
    /// * `recipient` - Recipient address
    /// * `amount` - Transfer amount (in base units)
    /// * `intent_id` - Intent ID to include in calldata (hex format with 0x prefix)
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Transaction hash
    /// * `Err(anyhow::Error)` - Failed to execute transfer
    ///
    /// # TODO
    ///
    /// Future improvement: Implement this directly using a Rust Ethereum library instead of
    /// calling Hardhat scripts. Good options include:
    /// - `ethers-rs` (https://github.com/gakonst/ethers-rs)
    /// - `alloy` (https://github.com/alloy-rs/alloy)
    pub async fn transfer_with_intent_id(
        &self,
        token_address: &str,
        recipient: &str,
        amount: u64,
        intent_id: &str,
    ) -> Result<String> {
        // Determine project root (assume we're in solver/ directory, go up one level)
        let current_dir = std::env::current_dir().context("Failed to get current directory")?;
        let project_root = current_dir
            .parent()
            .context("Failed to determine project root (expected solver/ to be subdirectory)")?;

        let evm_framework_dir = project_root.join("evm-intent-framework");
        if !evm_framework_dir.exists() {
            anyhow::bail!(
                "evm-intent-framework directory not found at: {}",
                evm_framework_dir.display()
            );
        }

        // Convert intent_id to EVM format (uint256)
        let intent_id_evm = if intent_id.starts_with("0x") {
            intent_id.to_string()
        } else {
            format!("0x{}", intent_id)
        };

        // Call Hardhat script via nix develop
        let output = Command::new("nix")
            .args(&[
                "develop",
                project_root.to_str().unwrap(),
                "-c",
                "bash",
                "-c",
                &format!(
                    "cd '{}' && TOKEN_ADDRESS='{}' RECIPIENT='{}' AMOUNT='{}' INTENT_ID='{}' npx hardhat run scripts/transfer-with-intent-id.js --network localhost",
                    evm_framework_dir.display(),
                    token_address,
                    recipient,
                    amount,
                    intent_id_evm
                ),
            ])
            .output()
            .context("Failed to execute nix develop command")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let stdout = String::from_utf8_lossy(&output.stdout);
            anyhow::bail!(
                "Hardhat transfer-with-intent-id script failed:\nstderr: {}\nstdout: {}",
                stderr,
                stdout
            );
        }

        // Extract transaction hash from output
        // The script outputs: "Transaction hash: 0x..."
        let output_str = String::from_utf8_lossy(&output.stdout);
        if let Some(hash_line) = output_str.lines().find(|l| l.contains("hash") || l.contains("Hash")) {
            if let Some(hash) = hash_line.split_whitespace().find(|s| s.starts_with("0x")) {
                return Ok(hash.to_string());
            }
        }

        anyhow::bail!("Could not extract transaction hash from Hardhat output: {}", output_str)
    }

    /// Claims an escrow by releasing funds to the solver with verifier approval
    ///
    /// Calls the `claim` function on the IntentEscrow contract using Hardhat script,
    /// matching the approach used in E2E test scripts. The Hardhat script handles
    /// signing using Hardhat's signer configuration (Account 2 = Solver).
    ///
    /// # Arguments
    ///
    /// * `escrow_address` - Address of the IntentEscrow contract
    /// * `intent_id` - Intent ID (hex string with 0x prefix, will be converted to uint256)
    /// * `signature` - Verifier's ECDSA signature (65 bytes: r || s || v)
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Transaction hash
    /// * `Err(anyhow::Error)` - Failed to claim escrow
    ///
    /// # Note
    ///
    /// This function calls the Hardhat script `claim-escrow.js` via `npx hardhat run`,
    /// matching the approach used in E2E test scripts. The script uses Hardhat's signer[2]
    /// (Solver account) for signing the transaction.
    ///
    /// # TODO
    ///
    /// Future improvement: Implement this directly using a Rust Ethereum library instead of
    /// calling Hardhat scripts. Good options include:
    /// - `ethers-rs` (https://github.com/gakonst/ethers-rs) - Popular, well-maintained
    /// - `alloy` (https://github.com/alloy-rs/alloy) - Modern, type-safe, actively developed
    ///
    /// This would eliminate the dependency on Node.js/Hardhat and provide better error handling
    /// and type safety. The implementation would:
    /// 1. Load the solver's private key from config
    /// 2. Create a wallet/provider using the RPC URL
    /// 3. Call the `claim(uint256 intentId, bytes memory signature)` function directly
    /// 4. Sign and send the transaction
    pub async fn claim_escrow(
        &self,
        escrow_address: &str,
        intent_id: &str,
        signature: &[u8],
    ) -> Result<String> {
        // Convert signature bytes to hex string (without 0x prefix, as expected by script)
        let signature_hex = hex::encode(signature);

        // Convert intent_id to EVM format (uint256)
        // The intent_id should already be in hex format (0x...), but we need to ensure it's valid
        let intent_id_evm = if intent_id.starts_with("0x") {
            intent_id.to_string()
        } else {
            format!("0x{}", intent_id)
        };

        // Determine project root (assume we're in solver/ directory, go up one level)
        // This matches how E2E scripts determine PROJECT_ROOT
        let current_dir = std::env::current_dir().context("Failed to get current directory")?;
        let project_root = current_dir
            .parent()
            .context("Failed to determine project root (expected solver/ to be subdirectory)")?;

        let evm_framework_dir = project_root.join("evm-intent-framework");
        if !evm_framework_dir.exists() {
            anyhow::bail!(
                "evm-intent-framework directory not found at: {}",
                evm_framework_dir.display()
            );
        }

        // Call Hardhat script via npx (using nix develop to ensure correct environment)
        // This matches the E2E script approach: nix develop "$PROJECT_ROOT" -c bash -c "cd ... && npx hardhat run ..."
        let output = Command::new("nix")
            .args(&[
                "develop",
                project_root.to_str().unwrap(),
                "-c",
                "bash",
                "-c",
                &format!(
                    "cd '{}' && ESCROW_ADDRESS='{}' INTENT_ID_EVM='{}' SIGNATURE_HEX='{}' npx hardhat run scripts/claim-escrow.js --network localhost",
                    evm_framework_dir.display(),
                    escrow_address,
                    intent_id_evm,
                    signature_hex
                ),
            ])
            .output()
            .context("Failed to execute nix develop command")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let stdout = String::from_utf8_lossy(&output.stdout);
            anyhow::bail!(
                "Hardhat claim-escrow script failed:\nstderr: {}\nstdout: {}",
                stderr,
                stdout
            );
        }

        // Extract transaction hash from output
        // The script outputs: "Claim transaction hash: 0x..."
        let output_str = String::from_utf8_lossy(&output.stdout);
        if let Some(hash_line) = output_str.lines().find(|l| l.contains("hash") || l.contains("Hash")) {
            if let Some(hash) = hash_line.split_whitespace().find(|s| s.starts_with("0x")) {
                return Ok(hash.to_string());
            }
        }

        anyhow::bail!("Could not extract transaction hash from Hardhat output: {}", output_str)
    }
}

