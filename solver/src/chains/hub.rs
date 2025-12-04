//! Hub Chain Client
//!
//! Client for interacting with the hub chain (Movement) to query intent events
//! and call fulfillment functions.

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::process::Command;
use std::time::Duration;

use crate::config::ChainConfig;

/// Event emitted when an intent is created on the hub chain
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentCreatedEvent {
    /// Intent object address
    pub intent_address: String,
    /// Intent ID for cross-chain linking
    pub intent_id: String,
    /// Offered token metadata
    pub offered_metadata: serde_json::Value,
    /// Offered amount
    pub offered_amount: String,
    /// Offered chain ID
    pub offered_chain_id: String,
    /// Desired token metadata
    pub desired_metadata: serde_json::Value,
    /// Desired amount
    pub desired_amount: String,
    /// Desired chain ID
    pub desired_chain_id: String,
    /// Requester address
    pub requester: String,
    /// Expiry timestamp
    pub expiry_time: String,
}

/// Event emitted when an intent is fulfilled
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentFulfilledEvent {
    /// Intent ID
    pub intent_id: String,
    /// Intent object address
    pub intent_address: String,
    /// Solver address
    pub solver: String,
    /// Provided token metadata
    pub provided_metadata: serde_json::Value,
    /// Provided amount
    pub provided_amount: String,
    /// Timestamp
    pub timestamp: String,
}

/// Client for interacting with the hub chain
pub struct HubChainClient {
    /// HTTP client for RPC calls
    client: Client,
    /// Base RPC URL
    base_url: String,
    /// Module address
    module_address: String,
    /// CLI profile name
    profile: String,
}

impl HubChainClient {
    /// Creates a new hub chain client
    ///
    /// # Arguments
    ///
    /// * `config` - Hub chain configuration
    ///
    /// # Returns
    ///
    /// * `Ok(HubChainClient)` - Successfully created client
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

    /// Queries the hub chain for intent creation events
    ///
    /// This queries known accounts for LimitOrderEvent and OracleLimitOrderEvent
    /// to detect when new intents are created.
    ///
    /// # Arguments
    ///
    /// * `known_accounts` - List of account addresses to query
    /// * `since_version` - Optional transaction version to start from (for pagination)
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<IntentCreatedEvent>)` - List of intent creation events
    /// * `Err(anyhow::Error)` - Failed to query events
    pub async fn get_intent_events(
        &self,
        known_accounts: &[String],
        since_version: Option<u64>,
    ) -> Result<Vec<IntentCreatedEvent>> {
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

            // Extract intent creation events from transactions
            for tx in transactions {
                if let Some(tx_events) = tx.get("events").and_then(|e| e.as_array()) {
                    for event_json in tx_events {
                        let event_type = event_json
                            .get("type")
                            .and_then(|t| t.as_str())
                            .unwrap_or("");

                        // Check for LimitOrderEvent (inflow) or OracleLimitOrderEvent (outflow)
                        // IMPORTANT: Check OracleLimitOrderEvent BEFORE LimitOrderEvent because
                        // "OracleLimitOrderEvent".contains("LimitOrderEvent") is true!
                        if event_type.contains("OracleLimitOrderEvent") || event_type.contains("LimitOrderEvent") {
                            if let Ok(event_data) = serde_json::from_value::<IntentCreatedEvent>(
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

    /// Fulfills an inflow request intent
    ///
    /// Calls the `fulfill_inflow_intent` entry function on the hub chain.
    ///
    /// # Arguments
    ///
    /// * `intent_address` - Object address of the intent to fulfill
    /// * `payment_amount` - Amount of tokens to provide
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Transaction hash
    /// * `Err(anyhow::Error)` - Failed to fulfill intent
    pub fn fulfill_inflow_intent(
        &self,
        intent_address: &str,
        payment_amount: u64,
    ) -> Result<String> {
        let output = Command::new("movement")
            .args(&[
                "move",
                "run",
                "--profile",
                &self.profile,
                "--assume-yes",
                "--function-id",
                &format!("{}::fa_intent_inflow::fulfill_inflow_intent", self.module_address),
                "--args",
                &format!("object:{}", intent_address),
                &format!("u64:{}", payment_amount),
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

    /// Fulfills an outflow request intent
    ///
    /// Calls the `fulfill_outflow_intent` entry function on the hub chain.
    ///
    /// # Arguments
    ///
    /// * `intent_address` - Object address of the intent to fulfill
    /// * `verifier_signature_bytes` - Verifier's Ed25519 signature as bytes
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Transaction hash
    /// * `Err(anyhow::Error)` - Failed to fulfill intent
    pub fn fulfill_outflow_intent(
        &self,
        intent_address: &str,
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
                &format!("{}::fa_intent_outflow::fulfill_outflow_intent", self.module_address),
                "--args",
                &format!("object:{}", intent_address),
                &format!("vector<u8>:0x{}", signature_hex),
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
}

