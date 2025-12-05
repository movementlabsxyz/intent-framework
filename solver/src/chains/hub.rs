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

    /// Checks if a solver is registered in the solver registry
    ///
    /// # Arguments
    ///
    /// * `solver_address` - Solver address to check
    ///
    /// # Returns
    ///
    /// * `Ok(bool)` - True if solver is registered, false otherwise
    /// * `Err(anyhow::Error)` - Failed to query registration status
    pub async fn is_solver_registered(&self, solver_address: &str) -> Result<bool> {
        // Normalize address (ensure 0x prefix)
        let solver_addr = if solver_address.starts_with("0x") {
            solver_address.to_string()
        } else {
            format!("0x{}", solver_address)
        };

        // Call the view function via RPC
        let view_url = format!("{}/view", self.base_url);
        let request_body = serde_json::json!({
            "function": format!("{}::solver_registry::is_registered", self.module_address),
            "type_arguments": [],
            "arguments": [solver_addr]
        });

        let response = self
            .client
            .post(&view_url)
            .json(&request_body)
            .send()
            .await
            .context("Failed to query solver registration")?;

        if !response.status().is_success() {
            anyhow::bail!(
                "Failed to query solver registration: HTTP {}",
                response.status()
            );
        }

        let result: Vec<serde_json::Value> = response
            .json()
            .await
            .context("Failed to parse registration check response")?;

        // The view function returns a bool, which is serialized as a JSON boolean
        if let Some(first_result) = result.first() {
            if let Some(is_registered) = first_result.as_bool() {
                return Ok(is_registered);
            }
        }

        anyhow::bail!("Unexpected response format from is_registered view function")
    }

    /// Registers the solver on-chain
    ///
    /// # Arguments
    ///
    /// * `public_key_bytes` - Ed25519 public key as bytes (32 bytes)
    /// * `evm_address` - EVM address on connected chain (20 bytes), or empty vec if not applicable
    /// * `mvm_address` - Move VM address on connected chain, or None if not applicable
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Transaction hash
    /// * `Err(anyhow::Error)` - Failed to register solver
    pub fn register_solver(
        &self,
        public_key_bytes: &[u8],
        evm_address: &[u8],
        mvm_address: Option<&str>,
    ) -> Result<String> {
        // Convert public key to hex
        let public_key_hex = hex::encode(public_key_bytes);
        
        // Convert EVM address to hex (pad to 20 bytes if needed)
        let evm_address_hex = if evm_address.is_empty() {
            "".to_string()
        } else {
            hex::encode(evm_address)
        };
        
        // Prepare MVM address (use 0x0 if None)
        let mvm_addr = mvm_address.unwrap_or("0x0");
        
        // Build command arguments - store formatted strings to avoid temporary value issues
        let function_id = format!("{}::solver_registry::register_solver", self.module_address);
        let public_key_arg = format!("vector<u8>:0x{}", public_key_hex);
        let evm_address_arg = if evm_address_hex.is_empty() {
            "vector<u8>:0x".to_string()
        } else {
            format!("vector<u8>:0x{}", evm_address_hex)
        };
        let mvm_address_arg = format!("address:{}", mvm_addr);
        
        let args = vec![
            "move",
            "run",
            "--profile",
            &self.profile,
            "--assume-yes",
            "--function-id",
            &function_id,
            "--args",
            &public_key_arg,
            &evm_address_arg,
            &mvm_address_arg,
        ];
        
        let output = Command::new("movement")
            .args(&args)
            .output()
            .context("Failed to execute movement move run for solver registration")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let stdout = String::from_utf8_lossy(&output.stdout);
            anyhow::bail!(
                "movement move run failed for solver registration:\nstderr: {}\nstdout: {}",
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

        anyhow::bail!("Could not extract transaction hash from registration output: {}", output_str)
    }
}

