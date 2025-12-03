//! Connected Move VM Chain Client
//!
//! Client for interacting with connected Move VM chains to query escrow events
//! and execute transfers.

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::process::Command;
use std::time::Duration;

use crate::config::ChainConfig;

/// Escrow event emitted when an escrow is created on the connected chain
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EscrowEvent {
    /// Escrow object address
    pub escrow_id: String,
    /// Intent ID for cross-chain linking
    pub intent_id: String,
    /// Requester address
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
    /// Reserved solver address (if any)
    pub reserved_solver: Option<String>,
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
            let url = format!("{}/v1/accounts/{}/transactions", self.base_url, account_address);

            let mut query_params = vec![("limit", "100".to_string())];
            if let Some(version) = since_version {
                query_params.push(("start", version.to_string()));
            }

            let response = self
                .client
                .get(&url)
                .query(&query_params)
                .send()
                .await
                .context(format!("Failed to query transactions for account {}", account))?;

            if !response.status().is_success() {
                continue; // Account might not exist or have no transactions
            }

            let transactions: Vec<serde_json::Value> = response
                .json()
                .await
                .context("Failed to parse transactions response")?;

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
                            if let Ok(event_data) = serde_json::from_value::<EscrowEvent>(
                                event_json.get("data").cloned().unwrap_or(serde_json::Value::Null),
                            ) {
                                events.push(event_data);
                            }
                        }
                    }
                }
            }
        }

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
        let output = Command::new("movement")
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
                &format!("object:{}", metadata),
                &format!("u64:{}", amount),
                &format!("address:{}", intent_id),
            ])
            .output()
            .context("Failed to execute movement move run")?;

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
        // The CLI outputs the transaction hash in format: "Transaction hash: 0x..."
        let output_str = String::from_utf8_lossy(&output.stdout);
        if let Some(hash_line) = output_str.lines().find(|l| l.contains("hash") || l.contains("Hash")) {
            if let Some(hash) = hash_line.split_whitespace().find(|s| s.starts_with("0x")) {
                return Ok(hash.to_string());
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

        let output = Command::new("movement")
            .args(&[
                "move",
                "run",
                "--profile",
                &self.profile,
                "--assume-yes",
                "--function-id",
                &format!("{}::intent_as_escrow_entry::complete_escrow_from_fa", self.module_address),
                "--args",
                &format!("object:{}", escrow_intent_address),
                &format!("u64:{}", payment_amount),
                &format!("hex:{}", signature_hex),
            ])
            .output()
            .context("Failed to execute movement move run")?;

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
        if let Some(hash_line) = output_str.lines().find(|l| l.contains("hash") || l.contains("Hash")) {
            if let Some(hash) = hash_line.split_whitespace().find(|s| s.starts_with("0x")) {
                return Ok(hash.to_string());
            }
        }

        anyhow::bail!("Could not extract transaction hash from output: {}", output_str)
    }
}

