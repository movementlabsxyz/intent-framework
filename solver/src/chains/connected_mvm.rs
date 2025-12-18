//! Connected Move VM Chain Client
//!
//! Client for interacting with connected Move VM chains to query escrow events
//! and execute transfers.

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::process::Command;
use std::time::Duration;
use tracing::{debug, warn};

use crate::config::ChainConfig;

/// Move VM Optional wrapper: {"vec": [value]} or {"vec": []}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MoveOption<T> {
    pub vec: Vec<T>,
}

impl<T> MoveOption<T> {
    pub fn into_option(mut self) -> Option<T> {
        self.vec.pop()
    }
}

/// Escrow event emitted when an escrow is created on the connected chain
/// This matches the OracleLimitOrderEvent structure from Move
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EscrowEvent {
    /// Escrow object address (called intent_address in Move OracleLimitOrderEvent)
    #[serde(rename = "intent_address")]
    pub escrow_id: String,
    /// Intent ID for cross-chain linking
    pub intent_id: String,
    /// Requester address (called requester in Move)
    #[serde(rename = "requester")]
    pub issuer: String,
    /// Offered token metadata
    pub offered_metadata: serde_json::Value,
    /// Offered amount
    pub offered_amount: String,
    /// Desired token metadata
    pub desired_metadata: serde_json::Value,
    /// Desired amount
    pub desired_amount: String,
    /// Expiry timestamp
    pub expiry_time: String,
    /// Whether the escrow is revocable
    pub revocable: bool,
    /// Reserved solver address (wrapped in Move Option: {"vec": [...]})
    #[serde(default)]
    pub reserved_solver: Option<MoveOption<String>>,
}

/// Client for interacting with a connected Move VM chain
pub struct ConnectedMvmClient {
    /// HTTP client for RPC calls
    client: Client,
    /// Base RPC URL
    base_url: String,
    /// Module address (for utils module)
    module_address: String,
    /// CLI profile name
    profile: String,
}

impl ConnectedMvmClient {
    /// Creates a new connected MVM chain client
    ///
    /// # Arguments
    ///
    /// * `config` - Connected chain configuration
    ///
    /// # Returns
    ///
    /// * `Ok(ConnectedMvmClient)` - Successfully created client
    /// * `Err(anyhow::Error)` - Failed to create client
    pub fn new(config: &ChainConfig) -> Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .no_proxy() // Avoid macOS system-configuration issues in tests
            .build()
            .context("Failed to create HTTP client")?;

        Ok(Self {
            client,
            base_url: config.rpc_url.clone(),
            module_address: config.module_address.clone(),
            profile: config.profile.clone(),
        })
    }

    /// Queries the connected chain for escrow creation events
    ///
    /// This queries known accounts for OracleLimitOrderEvent to detect when
    /// new escrows are created (for inflow intents).
    ///
    /// # Arguments
    ///
    /// * `known_accounts` - List of account addresses to query
    /// * `since_version` - Optional transaction version to start from (for pagination)
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<EscrowEvent>)` - List of escrow events
    /// * `Err(anyhow::Error)` - Failed to query events
    pub async fn get_escrow_events(
        &self,
        known_accounts: &[String],
        since_version: Option<u64>,
    ) -> Result<Vec<EscrowEvent>> {
        let mut events = Vec::new();

        for account in known_accounts {
            let account_address = account.strip_prefix("0x").unwrap_or(account);
            // Note: base_url already includes /v1 (e.g., http://127.0.0.1:8082/v1)
            let url = format!("{}/accounts/{}/transactions", self.base_url, account_address);

            let mut query_params = vec![("limit", "100".to_string())];
            if let Some(version) = since_version {
                query_params.push(("start", version.to_string()));
            }

            debug!("Querying escrow events from URL: {}", url);

            let response = self
                .client
                .get(&url)
                .query(&query_params)
                .send()
                .await
                .context(format!("Failed to query transactions for account {} (URL: {})", account, url))?;

            if !response.status().is_success() {
                let status = response.status();
                let body = response.text().await.unwrap_or_else(|_| "<failed to read body>".to_string());
                warn!(
                    "Failed to query transactions for account {} (URL: {}): HTTP {} - {}",
                    account, url, status, body
                );
                continue;
            }

            let transactions: Vec<serde_json::Value> = response
                .json()
                .await
                .context(format!("Failed to parse transactions response for account {}", account))?;

            debug!("Found {} transactions for account {}", transactions.len(), account);

            // Extract escrow events from transactions
            for tx in transactions {
                if let Some(tx_events) = tx.get("events").and_then(|e| e.as_array()) {
                    for event_json in tx_events {
                        let event_type = event_json
                            .get("type")
                            .and_then(|t| t.as_str())
                            .unwrap_or("");

                        // Escrows use oracle-guarded intents, so we look for OracleLimitOrderEvent
                        if event_type.contains("OracleLimitOrderEvent") {
                            match serde_json::from_value::<EscrowEvent>(
                                event_json.get("data").cloned().unwrap_or(serde_json::Value::Null),
                            ) {
                                Ok(event_data) => {
                                    debug!("Found escrow event: intent_id={}, escrow_id={}", 
                                           event_data.intent_id, event_data.escrow_id);
                                    events.push(event_data);
                                }
                                Err(e) => {
                                    warn!("Failed to parse OracleLimitOrderEvent: {} - data: {:?}", 
                                          e, event_json.get("data"));
                                }
                            }
                        }
                    }
                }
            }
        }

        debug!("Total escrow events found: {}", events.len());
        Ok(events)
    }

    /// Executes a transfer with intent ID on the connected chain
    ///
    /// Calls the `transfer_with_intent_id` entry function to transfer tokens
    /// and include the intent_id in the transaction (for outflow fulfillment).
    ///
    /// # Arguments
    ///
    /// * `recipient` - Recipient address
    /// * `metadata` - Token metadata object address
    /// * `amount` - Amount to transfer
    /// * `intent_id` - Intent ID to include in the transaction
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Transaction hash
    /// * `Err(anyhow::Error)` - Failed to execute transfer
    pub fn transfer_with_intent_id(
        &self,
        recipient: &str,
        metadata: &str,
        amount: u64,
        intent_id: &str,
    ) -> Result<String> {
        use tracing::{info, warn};
        
        // Debug: Get solver's address from profile
        let address_check = Command::new("aptos")
            .args(&["config", "show-profiles"])
            .output();
        
        if let Ok(address_output) = address_check {
            let address_str = String::from_utf8_lossy(&address_output.stdout);
            info!("Transfer attempt - profile: {}, recipient: {}, amount: {}, metadata: {}", 
                  self.profile, recipient, amount, metadata);
            info!("Aptos profiles: {}", address_str);
        }
        
        // Debug: Check solver's balance before transfer
        let balance_check = Command::new("aptos")
            .args(&["account", "balance", "--profile", &self.profile])
            .output();
        
        if let Ok(balance_output) = balance_check {
            let balance_str = String::from_utf8_lossy(&balance_output.stdout);
            info!("Solver balance check (profile: {}): {}", self.profile, balance_str);
        } else {
            warn!("Failed to check solver balance for profile: {}", self.profile);
        }
        
        // Use aptos CLI for compatibility with E2E tests which create aptos profiles
        let output = Command::new("aptos")
            .args(&[
                "move",
                "run",
                "--profile",
                &self.profile,
                "--assume-yes",
                "--function-id",
                &format!("{}::utils::transfer_with_intent_id", self.module_address),
                "--args",
                &format!("address:{}", recipient),
                &format!("address:{}", metadata),
                &format!("u64:{}", amount),
                &format!("address:{}", intent_id),
            ])
            .output()
            .context("Failed to execute aptos move run")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let stdout = String::from_utf8_lossy(&output.stdout);
            anyhow::bail!(
                "movement move run failed:\nstderr: {}\nstdout: {}",
                stderr,
                stdout
            );
        }

        // Extract transaction hash from output
        let output_str = String::from_utf8_lossy(&output.stdout);

        // Try to parse as JSON first (aptos CLI outputs JSON with Result wrapper)
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&output_str) {
            // Handle {"Result": {"transaction_hash": "0x...", ...}}
            if let Some(hash) = json
                .get("Result")
                .and_then(|r| r.get("transaction_hash"))
                .and_then(|h| h.as_str())
            {
                return Ok(hash.to_string());
            }
        }

        // Fallback: line-based parsing for "Transaction hash: 0x..." format
        if let Some(hash_line) = output_str.lines().find(|l| l.contains("hash") || l.contains("Hash")) {
            // Try finding 0x directly or quoted "0x
            if let Some(hash) = hash_line.split_whitespace().find(|s| s.starts_with("0x")) {
                return Ok(hash.to_string());
            }
            // Handle quoted hash like "0x..."
            if let Some(start) = hash_line.find("\"0x") {
                if let Some(end) = hash_line[start + 1..].find('"') {
                    return Ok(hash_line[start + 1..start + 1 + end].to_string());
                }
            }
        }

        anyhow::bail!("Could not extract transaction hash from output: {}", output_str)
    }

    /// Completes an escrow by releasing funds to the solver with verifier approval
    ///
    /// Calls the `complete_escrow_from_fa` entry function which:
    /// 1. Starts the escrow session (gets locked assets)
    /// 2. Deposits locked assets to solver
    /// 3. Withdraws payment from solver
    /// 4. Completes escrow with verifier signature
    ///
    /// # Arguments
    ///
    /// * `escrow_intent_address` - Object address of the escrow intent
    /// * `payment_amount` - Amount of tokens to provide as payment (typically matches desired_amount)
    /// * `verifier_signature_bytes` - Verifier's Ed25519 signature as bytes (base64 decoded)
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Transaction hash
    /// * `Err(anyhow::Error)` - Failed to complete escrow
    pub fn complete_escrow_from_fa(
        &self,
        escrow_intent_address: &str,
        payment_amount: u64,
        verifier_signature_bytes: &[u8],
    ) -> Result<String> {
        // Convert signature bytes to hex string
        let signature_hex = hex::encode(verifier_signature_bytes);

        // Use aptos CLI for compatibility with E2E tests which create aptos profiles
        let output = Command::new("aptos")
            .args(&[
                "move",
                "run",
                "--profile",
                &self.profile,
                "--assume-yes",
                "--function-id",
                &format!("{}::intent_as_escrow_entry::complete_escrow_from_fa", self.module_address),
                "--args",
                &format!("address:{}", escrow_intent_address),
                &format!("u64:{}", payment_amount),
                &format!("hex:{}", signature_hex),
            ])
            .output()
            .context("Failed to execute aptos move run")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let stdout = String::from_utf8_lossy(&output.stdout);
            anyhow::bail!(
                "movement move run failed:\nstderr: {}\nstdout: {}",
                stderr,
                stdout
            );
        }

        // Extract transaction hash from output
        let output_str = String::from_utf8_lossy(&output.stdout);

        // Try to parse as JSON first (aptos CLI outputs JSON with Result wrapper)
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&output_str) {
            // Handle {"Result": {"transaction_hash": "0x...", ...}}
            if let Some(hash) = json
                .get("Result")
                .and_then(|r| r.get("transaction_hash"))
                .and_then(|h| h.as_str())
            {
                return Ok(hash.to_string());
            }
        }

        // Fallback: line-based parsing for "Transaction hash: 0x..." format
        if let Some(hash_line) = output_str.lines().find(|l| l.contains("hash") || l.contains("Hash")) {
            // Try finding 0x directly or quoted "0x
            if let Some(hash) = hash_line.split_whitespace().find(|s| s.starts_with("0x")) {
                return Ok(hash.to_string());
            }
            // Handle quoted hash like "0x..."
            if let Some(start) = hash_line.find("\"0x") {
                if let Some(end) = hash_line[start + 1..].find('"') {
                    return Ok(hash_line[start + 1..start + 1 + end].to_string());
                }
            }
        }

        anyhow::bail!("Could not extract transaction hash from output: {}", output_str)
    }
}

