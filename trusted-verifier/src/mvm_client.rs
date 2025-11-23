//! Move VM REST Client Module
//!
//! This module provides a client for communicating with Move VM-based blockchain nodes
//! (e.g., Aptos) via their HTTP REST API. It handles account queries, event polling, and
//! transaction verification.
//!
//! ## Features
//!
//! - Query account information
//! - Poll for events on specific accounts
//! - Get transaction details
//! - Parse and handle Move VM REST API responses

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Deserializer, Serialize};
use std::time::Duration;

// Helper to deserialize u64 from either string or number
fn deserialize_u64_string<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    use serde::de::Error;
    let value: serde_json::Value = Deserialize::deserialize(deserializer)?;
    match value {
        serde_json::Value::String(s) => Ok(s),
        serde_json::Value::Number(n) => Ok(n.to_string()),
        _ => Err(D::Error::custom(format!(
            "expected string or number for chain_id, got: {:?}",
            value
        ))),
    }
}

// Helper to deserialize Move's Option<T> format: {"vec": [value]} for Some, {"vec": []} for None
fn deserialize_move_option_string<'de, D>(deserializer: D) -> Result<Option<String>, D::Error>
where
    D: Deserializer<'de>,
{
    use serde::de::Error;
    #[derive(Deserialize)]
    struct MoveOption {
        vec: Vec<String>,
    }

    let opt: MoveOption = Deserialize::deserialize(deserializer)?;
    match opt.vec.as_slice() {
        [value] => Ok(Some(value.clone())),
        [] => Ok(None),
        _ => Err(D::Error::custom(format!(
            "expected Move Option format with 0 or 1 element in vec, got {} elements",
            opt.vec.len()
        ))),
    }
}

// ============================================================================
// API RESPONSE STRUCTURES
// ============================================================================

/// Move VM REST API response wrapper
#[derive(Debug, Deserialize)]
pub struct MvmResponse<T> {
    #[allow(dead_code)]
    pub inner: T,
}

/// Account information from Move VM chain
#[derive(Debug, Deserialize)]
pub struct AccountInfo {
    #[allow(dead_code)]
    pub sequence_number: String,
    #[allow(dead_code)]
    pub authentication_key: String,
}

/// Resource data from Move VM account
#[derive(Debug, Deserialize, Clone)]
pub struct ResourceData {
    #[serde(rename = "type")]
    pub resource_type: String,
    pub data: serde_json::Value,
}

/// Event handle wrapper
#[derive(Debug, Deserialize, Clone)]
pub struct EventHandle {
    #[allow(dead_code)]
    pub counter: String,
    #[allow(dead_code)]
    pub guid: EventHandleGuid,
}

#[derive(Debug, Deserialize, Clone)]
pub struct EventHandleGuid {
    #[allow(dead_code)]
    pub id: EventHandleGuidId,
}

#[derive(Debug, Deserialize, Clone)]
pub struct EventHandleGuidId {
    #[allow(dead_code)]
    pub creation_num: String,
}

/// Module information
#[derive(Debug, Deserialize)]
pub struct ModuleInfo {
    #[allow(dead_code)]
    pub bytecode: String,
    #[allow(dead_code)]
    pub abi: serde_json::Value,
}

/// Resources wrapper
#[derive(Debug, Deserialize)]
pub struct Resources {
    #[serde(rename = "Result")]
    #[allow(dead_code)]
    pub result: Vec<ResourceData>,
}

/// Event GUID (for module events)
#[derive(Debug, Deserialize, Clone)]
pub struct EventGuid {
    #[serde(rename = "creation_number")]
    #[allow(dead_code)]
    pub creation_number: String,
    #[serde(rename = "account_address")]
    #[allow(dead_code)]
    pub account_address: String,
}

/// Event from Move VM blockchain
/// Can be either a module event (with guid) or legacy EventHandle event (with key)
#[derive(Debug, Deserialize, Clone)]
pub struct MvmEvent {
    #[serde(skip_serializing_if = "Option::is_none")]
    #[allow(dead_code)]
    pub guid: Option<EventGuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[allow(dead_code)]
    pub key: Option<String>,
    #[allow(dead_code)]
    pub sequence_number: String,
    pub r#type: String,
    pub data: serde_json::Value,
}

/// Transaction details from Move VM chain
#[derive(Debug, Deserialize)]
pub struct MvmTransaction {
    #[allow(dead_code)]
    pub version: String,
    #[allow(dead_code)]
    pub hash: String,
    #[allow(dead_code)]
    pub success: bool,
    #[allow(dead_code)]
    pub events: Vec<MvmEvent>,
    /// Transaction payload (contains function call information)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub payload: Option<serde_json::Value>,
    /// Transaction sender
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sender: Option<String>,
}

// ============================================================================
// MOVE VM CLIENT IMPLEMENTATION
// ============================================================================

/// Client for communicating with Move VM-based blockchain nodes (e.g., Aptos) via REST API
pub struct MvmClient {
    /// HTTP client for making requests
    client: Client,
    /// Base URL of the Move VM node (e.g., "http://127.0.0.1:8080")
    base_url: String,
}

impl MvmClient {
    /// Creates a new Move VM client for the given node URL
    ///
    /// # Arguments
    ///
    /// * `node_url` - Base URL of the Move VM node (e.g., "http://127.0.0.1:8080")
    ///
    /// # Returns
    ///
    /// * `Ok(MvmClient)` - Successfully created client
    /// * `Err(anyhow::Error)` - Failed to create client
    pub fn new(node_url: &str) -> Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .context("Failed to create HTTP client")?;

        Ok(Self {
            client,
            base_url: node_url.to_string(),
        })
    }

    /// Queries account information from the Move VM blockchain
    ///
    /// # Arguments
    ///
    /// * `address` - Account address to query
    ///
    /// # Returns
    ///
    /// * `Ok(AccountInfo)` - Account information
    /// * `Err(anyhow::Error)` - Failed to query account
    #[allow(dead_code)]
    pub async fn get_account(&self, address: &str) -> Result<AccountInfo> {
        let url = format!("{}/v1/accounts/{}", self.base_url, address);

        let response = self
            .client
            .get(&url)
            .send()
            .await
            .context("Failed to send account request")?
            .error_for_status()
            .context("Account request failed")?;

        let account: AccountInfo = response
            .json()
            .await
            .context("Failed to parse account response")?;

        Ok(account)
    }

    /// Queries events for a specific account on the Move VM blockchain
    ///
    /// This method queries module events by scanning transaction history.
    /// For modern Move VM modules that use `event::emit()`, events are stored
    /// in transaction history, not as event handles.
    ///
    /// ## Event Discovery Strategy
    ///
    /// **Why not use EventHandle?**
    /// EventHandle-based events could have been an option using the pattern:
    /// (In Move code: `struct GlobalEvents has key { events: event::EventHandle<MyEvent> }`)
    /// This would allow querying via `/v1/accounts/{address}/events/{creation_number}`,
    /// providing a stable, queryable endpoint at a known address.
    ///
    /// However, Move VM chains (e.g., Aptos) have **deprecated EventHandle in favor of module events**.
    /// See: https://aptos.guide/network/blockchain/events
    ///
    /// **Current approach**: Query known user accounts' transaction history to extract
    /// module events. This is suitable for our test scenario with Alice/Bob accounts.
    /// For production, consider using the Move VM Indexer GraphQL API (e.g., Aptos Indexer) for more efficient
    /// querying by event type across all accounts.
    ///
    /// # Arguments
    ///
    /// * `address` - Account address to query events for
    /// * `event_handle` - Optional event handle (for legacy EventHandle events)
    /// * `start` - Starting transaction version (optional)
    /// * `limit` - Maximum number of events to return
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<MvmEvent>)` - List of events
    /// * `Err(anyhow::Error)` - Failed to query events
    pub async fn get_account_events(
        &self,
        address: &str,
        event_handle: Option<&str>,
        start: Option<u64>,
        limit: Option<u64>,
    ) -> Result<Vec<MvmEvent>> {
        // For legacy EventHandle events, use the old approach
        if let Some(handle) = event_handle {
            return self
                .get_events_by_creation_number(address, handle, start, limit)
                .await;
        }

        // For modern module events, query the account's transactions to find events
        // This is necessary because module events are emitted in user transactions, not on module account
        let limit = limit.unwrap_or(100);
        let url = format!("{}/v1/accounts/{}/transactions", self.base_url, address);

        let response = self
            .client
            .get(&url)
            .query(&[("limit", limit.to_string())])
            .send()
            .await
            .context("Failed to query account transactions")?;

        if !response.status().is_success() {
            return Ok(vec![]); // Account might not exist or have no transactions
        }

        let transactions: Vec<serde_json::Value> = response
            .json()
            .await
            .context("Failed to parse transactions response")?;

        // Extract events from transactions
        let mut events = Vec::new();
        for tx in transactions {
            if let Some(tx_events) = tx.get("events").and_then(|e| e.as_array()) {
                for event_json in tx_events {
                    // Extract event fields manually to handle different formats
                    let event_type = event_json
                        .get("type")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let event_data = event_json
                        .get("data")
                        .cloned()
                        .unwrap_or(serde_json::Value::Null);

                    // Extract sequence number
                    let sequence_number = event_json
                        .get("sequence_number")
                        .and_then(|s| s.as_str())
                        .unwrap_or("0")
                        .to_string();

                    // Extract guid if present (for module events)
                    let guid = event_json
                        .get("guid")
                        .and_then(|g| serde_json::from_value::<EventGuid>(g.clone()).ok());

                    // Extract key if present (for EventHandle events)
                    let key = event_json
                        .get("key")
                        .and_then(|k| k.as_str())
                        .map(|s| s.to_string());

                    events.push(MvmEvent {
                        guid,
                        key,
                        sequence_number,
                        r#type: event_type,
                        data: event_data,
                    });
                }
            }
        }

        Ok(events)
    }

    /// Queries events for a specific creation number
    ///
    /// # Arguments
    ///
    /// * `address` - Account address
    /// * `creation_number` - Event handle creation number
    /// * `start` - Starting sequence number (optional)
    /// * `limit` - Maximum number of events to return
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<MvmEvent>)` - List of events
    /// * `Err(anyhow::Error)` - Failed to query events
    async fn get_events_by_creation_number(
        &self,
        address: &str,
        creation_number: &str,
        start: Option<u64>,
        limit: Option<u64>,
    ) -> Result<Vec<MvmEvent>> {
        let mut url = format!(
            "{}/v1/accounts/{}/events/{}",
            self.base_url, address, creation_number
        );

        // Add query parameters
        let mut query_params = vec![];
        if let Some(s) = start {
            query_params.push(format!("start={}", s));
        }
        if let Some(l) = limit {
            query_params.push(format!("limit={}", l));
        }
        if !query_params.is_empty() {
            url.push('?');
            url.push_str(&query_params.join("&"));
        }

        let response = self
            .client
            .get(&url)
            .send()
            .await
            .context("Failed to send events request")?;

        // If 404, return empty vec (no events yet)
        let status = response.status();
        if status == 404 {
            return Ok(vec![]);
        }

        let response = response
            .error_for_status()
            .context("Events request failed")?;

        let events: Vec<MvmEvent> = response
            .json()
            .await
            .context("Failed to parse events response")?;

        Ok(events)
    }

    /// Gets resources for an account
    ///
    /// # Arguments
    ///
    /// * `address` - Account address
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<ResourceData>)` - Account resources
    /// * `Err(anyhow::Error)` - Failed to query resources
    pub async fn get_resources(&self, address: &str) -> Result<Vec<ResourceData>> {
        let url = format!("{}/v1/accounts/{}/resources", self.base_url, address);

        let response = self
            .client
            .get(&url)
            .send()
            .await
            .context("Failed to send resources request")?
            .error_for_status()
            .context("Resources request failed")?;

        let resources: Vec<ResourceData> = response
            .json()
            .await
            .context("Failed to parse resources response")?;

        Ok(resources)
    }

    /// Finds event handles matching the given event type pattern
    ///
    /// This queries the account's resources to find event handles that match the pattern.
    /// Event handles contain creation numbers which are used to query events via the
    /// `/v1/accounts/{address}/events/{creation_number}` endpoint.
    ///
    /// Note: An alternative approach would be to query transactions and extract events
    /// from transaction history, but this is not supported because:
    /// 1. It's less efficient (fetching full transactions vs just events)
    /// 2. It's not the official Move VM API pattern for event monitoring
    /// 3. Event handles are the standard way to track module events
    ///
    /// # Arguments
    ///
    /// * `address` - Account address
    /// * `event_type_pattern` - Pattern to match (e.g., "LimitOrderEvent", "OracleLimitOrderEvent")
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<String>)` - List of creation numbers for matching event handles
    /// * `Err(anyhow::Error)` - Failed to find event handles
    #[allow(dead_code)]
    pub async fn find_event_handles(
        &self,
        address: &str,
        event_type_pattern: &str,
    ) -> Result<Vec<String>> {
        let resources = self.get_resources(address).await?;
        let mut creation_numbers = Vec::new();

        for resource in resources {
            // Look for event handles in the resource data
            if let Some(handle_obj) = resource.data.get("handle") {
                if let Ok(handle) = serde_json::from_value::<EventHandle>(handle_obj.clone()) {
                    creation_numbers.push(handle.guid.id.creation_num.clone());
                }
            }

            // Also check if the resource itself matches the pattern (for module events)
            if resource.resource_type.contains(event_type_pattern) {
                if let Some(handle_obj) = resource.data.get("events") {
                    if handle_obj.is_object() {
                        for (_key, value) in handle_obj.as_object().unwrap() {
                            if let Ok(handle) = serde_json::from_value::<EventHandle>(value.clone())
                            {
                                creation_numbers.push(handle.guid.id.creation_num.clone());
                            }
                        }
                    }
                }
            }
        }

        Ok(creation_numbers)
    }

    /// Queries transaction details by hash
    ///
    /// # Arguments
    ///
    /// * `hash` - Transaction hash
    ///
    /// # Returns
    ///
    /// * `Ok(MvmTransaction)` - Transaction information
    /// * `Err(anyhow::Error)` - Failed to query transaction
    #[allow(dead_code)]
    pub async fn get_transaction(&self, hash: &str) -> Result<MvmTransaction> {
        let url = format!("{}/v1/transactions/by_hash/{}", self.base_url, hash);

        let response = self
            .client
            .get(&url)
            .send()
            .await
            .context("Failed to send transaction request")?
            .error_for_status()
            .context("Transaction request failed")?;

        let tx: MvmTransaction = response
            .json()
            .await
            .context("Failed to parse transaction response")?;

        Ok(tx)
    }

    /// Checks if the node is healthy and responsive
    ///
    /// # Returns
    ///
    /// * `Ok(())` - Node is healthy
    /// * `Err(anyhow::Error)` - Node is not responding
    #[allow(dead_code)]
    pub async fn health_check(&self) -> Result<()> {
        let url = format!("{}/v1", self.base_url);

        let response = self
            .client
            .get(&url)
            .send()
            .await
            .context("Failed to send health check request")?
            .error_for_status()
            .context("Health check failed")?;

        // Just check if we got a response
        response
            .text()
            .await
            .context("Failed to read health check response")?;

        Ok(())
    }

    /// Returns the base URL of this client
    #[allow(dead_code)]
    pub fn base_url(&self) -> &str {
        &self.base_url
    }

    /// Queries an intent object's reservation to get the solver address.
    ///
    /// # Arguments
    ///
    /// * `intent_address` - Address of the intent object
    /// * `module_address` - Address of the intent module
    ///
    /// # Returns
    ///
    /// * `Ok(Option<String>)` - Solver address if reserved, None if not reserved
    /// * `Err(anyhow::Error)` - Failed to query intent
    pub async fn get_intent_solver(
        &self,
        intent_address: &str,
        _module_address: &str,
    ) -> Result<Option<String>> {
        // Query the intent object's resources
        let resources = self.get_resources(intent_address).await?;

        // Look for the TradeIntent resource which contains the reservation
        // The resource type should be something like: "0x{module_address}::fa_intent::TradeIntent<...>"
        for resource in resources {
            if resource.resource_type.contains("TradeIntent") {
                // Try to extract reservation from the resource data
                // The reservation is stored as an Option<IntentReserved> in the TradeIntent
                if let Some(data) = resource.data.as_object() {
                    // Look for reservation field
                    if let Some(reservation) = data.get("reservation") {
                        // Check if reservation is Some (not null)
                        if reservation.is_object() {
                            // Extract solver address from IntentReserved
                            if let Some(solver) = reservation.get("solver") {
                                if let Some(solver_str) = solver.as_str() {
                                    return Ok(Some(solver_str.to_string()));
                                }
                            }
                        }
                    }
                }
            }
        }

        Ok(None)
    }

    /// Queries the solver registry to get a solver's connected chain Move VM address.
    ///
    /// # Arguments
    ///
    /// * `solver_address` - Move VM address of the solver (hub chain)
    /// * `registry_address` - Address where the solver registry is deployed (usually @mvmt_intent)
    ///
    /// # Returns
    ///
    /// * `Ok(Option<String>)` - Connected chain Move VM address if solver is registered and address is set, None otherwise
    /// * `Err(anyhow::Error)` - Failed to query registry
    pub async fn get_solver_connected_chain_mvm_address(
        &self,
        solver_address: &str,
        registry_address: &str,
    ) -> Result<Option<String>> {
        // Normalize registry address (remove 0x prefix for resource type matching)
        let registry_addr_normalized = registry_address
            .strip_prefix("0x")
            .unwrap_or(registry_address);
        
        // Query the SolverRegistry resource directly
        let resources = self.get_resources(registry_address).await?;

        // Try both formats: with and without 0x prefix (Aptos may return either)
        let registry_resource_type_with_prefix =
            format!("0x{}::solver_registry::SolverRegistry", registry_addr_normalized);
        let registry_resource_type_without_prefix =
            format!("{}::solver_registry::SolverRegistry", registry_addr_normalized);
        
        let solver_addr = solver_address
            .strip_prefix("0x")
            .unwrap_or(solver_address)
            .to_lowercase();

        // Find the SolverRegistry resource (try both formats)
        let registry_resource = resources
            .iter()
            .find(|r| {
                r.resource_type == registry_resource_type_with_prefix
                    || r.resource_type == registry_resource_type_without_prefix
            });

        let Some(registry_resource) = registry_resource else {
            tracing::warn!(
                "SolverRegistry resource not found. Registry address: {}, Tried types: '{}' and '{}', Available resources: {:?}",
                registry_address,
                registry_resource_type_with_prefix,
                registry_resource_type_without_prefix,
                resources.iter().map(|r| &r.resource_type).collect::<Vec<_>>()
            );
            return Ok(None); // Registry resource not found
        };

        // Extract solvers map: SimpleMap<address, SolverInfo> is {"data": [{"key": address, "value": SolverInfo}, ...]}
        let data = match registry_resource.data.as_object() {
            Some(d) => d,
            None => return Ok(None),
        };

        let solvers = match data.get("solvers").and_then(|s| s.as_object()) {
            Some(s) => s,
            None => return Ok(None),
        };

        let data_array = match solvers.get("data").and_then(|d| d.as_array()) {
            Some(d) => d,
            None => return Ok(None),
        };

        // Find the solver entry
        let solver_entry = data_array.iter().find_map(|entry| {
            let entry_obj = entry.as_object()?;
            let key = entry_obj.get("key")?.as_str()?;
            let key_normalized = key.strip_prefix("0x").unwrap_or(key).to_lowercase();
            (key_normalized == solver_addr).then_some(entry_obj)
        });

        let Some(entry_obj) = solver_entry else {
            return Ok(None); // Solver not found in registry
        };

        // Extract connected_chain_mvm_address from SolverInfo
        // Option<address> is serialized as {"vec": [address]} for Some, {"vec": []} for None
        let value = match entry_obj.get("value").and_then(|v| v.as_object()) {
            Some(v) => v,
            None => return Ok(None),
        };

        let mvm_addr = match value
            .get("connected_chain_mvm_address")
            .and_then(|m| m.as_object())
        {
            Some(m) => m,
            None => return Ok(None),
        };

        let vec_array = match mvm_addr.get("vec").and_then(|v| v.as_array()) {
            Some(v) => v,
            None => return Ok(None),
        };

        if vec_array.is_empty() {
            return Ok(None); // Solver found but no connected chain MVM address
        }

        match vec_array.get(0).and_then(|a| a.as_str()) {
            Some(addr_str) => Ok(Some(addr_str.to_string())),
            None => Ok(None),
        }
    }

    /// Queries the solver registry to get a solver's public key.
    ///
    /// # Arguments
    ///
    /// * `solver_address` - Move VM address of the solver
    /// * `registry_address` - Address where the solver registry is deployed (usually @mvmt_intent)
    ///
    /// # Returns
    ///
    /// * `Ok(Option<Vec<u8>>)` - Public key bytes if solver is registered, None otherwise
    /// * `Err(anyhow::Error)` - Failed to query registry
    pub async fn get_solver_public_key(
        &self,
        solver_address: &str,
        registry_address: &str,
    ) -> Result<Option<Vec<u8>>> {
        // Use view function to call solver_registry::get_public_key
        let result = self
            .call_view_function(
                registry_address,
                "solver_registry",
                "get_public_key",
                vec![],
                vec![serde_json::json!(solver_address)],
            )
            .await;

        match result {
            Ok(value) => {
                // The view function returns a vector<u8> (empty if not registered)
                if let Some(pk_bytes) = value.as_array() {
                    if pk_bytes.is_empty() {
                        Ok(None)
                    } else {
                        let mut public_key = Vec::new();
                        for byte_val in pk_bytes {
                            if let Some(byte) = byte_val.as_u64() {
                                public_key.push(byte as u8);
                            }
                        }
                        Ok(Some(public_key))
                    }
                } else {
                    Ok(None)
                }
            }
            Err(e) => {
                // If view function fails, solver might not be registered
                // Log and return None
                tracing::debug!("Failed to query solver public key: {}", e);
                Ok(None)
            }
        }
    }

    /// Queries the solver registry to get a solver's EVM address.
    ///
    /// # Arguments
    ///
    /// * `solver_address` - Move VM address of the solver
    /// * `registry_address` - Address where the solver registry is deployed (usually @mvmt_intent)
    ///
    /// # Returns
    ///
    /// * `Ok(Option<String>)` - EVM address if solver is registered, None otherwise
    /// * `Err(anyhow::Error)` - Failed to query registry
    pub async fn get_solver_evm_address(
        &self,
        solver_address: &str,
        registry_address: &str,
    ) -> Result<Option<String>> {
        tracing::error!(
            "DEBUG: get_solver_evm_address called with solver_address='{}' (len: {}, type: str), registry_address='{}' (len: {}, type: str)",
            solver_address,
            solver_address.len(),
            registry_address,
            registry_address.len()
        );
        
        // Normalize solver address for comparison
        let solver_addr_normalized = solver_address
            .strip_prefix("0x")
            .unwrap_or(solver_address)
            .to_lowercase();

        tracing::error!(
            "DEBUG: Normalized solver_address='{}' -> normalized='{}' (len: {})",
            solver_address,
            solver_addr_normalized,
            solver_addr_normalized.len()
        );
        
        // Query the SolverRegistry resource directly
        let resources = self.get_resources(registry_address).await?;

        // Find the SolverRegistry resource
        let registry_resource = match Self::find_solver_registry_resource(&resources, registry_address) {
            Some(resource) => resource,
            None => return Ok(None),
        };

        // Extract solvers data array
        let data_array = match Self::extract_solvers_data_array(registry_resource) {
            Some(array) => array,
            None => return Ok(None),
        };

        // Find the solver entry
        let entry_obj = match Self::find_solver_entry(data_array, solver_address, &solver_addr_normalized) {
            Some(entry) => entry,
            None => return Ok(None),
        };

        // Extract SolverInfo value
        let solver_info = match entry_obj.get("value").and_then(|v| v.as_object()) {
            Some(info) => info,
            None => {
                let entry_keys = entry_obj.keys().collect::<Vec<_>>();
                let entry_json = serde_json::to_string(entry_obj).unwrap_or_else(|_| "failed to serialize".to_string());
                tracing::warn!(
                    "SolverInfo 'value' field not found or not an object for solver '{}'. Entry object keys: {:?}, Full entry: {}",
                    solver_address,
                    entry_keys,
                    entry_json
                );
                return Ok(None);
            }
        };

        // Extract connected_chain_evm_address field
        let evm_addr_field: &serde_json::Value = match solver_info.get("connected_chain_evm_address") {
            Some(field) => field,
            None => {
                let solver_info_keys = solver_info.keys().collect::<Vec<_>>();
                let solver_info_json = serde_json::to_string(solver_info).unwrap_or_else(|_| "failed to serialize".to_string());
                tracing::error!(
                    "connected_chain_evm_address field not found for solver '{}'. SolverInfo keys: {:?}, Full SolverInfo: {}",
                    solver_address,
                    solver_info_keys,
                    solver_info_json
                );
                return Ok(None);
            }
        };

        tracing::error!(
            "DEBUG: connected_chain_evm_address field for solver '{}': {}",
            solver_address,
            serde_json::to_string(evm_addr_field).unwrap_or_else(|_| "failed to serialize".to_string())
        );

        // Extract vec array from Option<vector<u8>> structure
        let evm_addr = match evm_addr_field.as_object() {
            Some(obj) => obj,
            None => {
                let field_json = serde_json::to_string(evm_addr_field).unwrap_or_else(|_| "failed to serialize".to_string());
                tracing::error!(
                    "connected_chain_evm_address is not an object for solver '{}'. Value: {}",
                    solver_address,
                    field_json
                );
                return Ok(None);
            }
        };

        let vec_array: &serde_json::Value = match evm_addr.get("vec") {
            Some(vec) => vec,
            None => {
                let evm_addr_keys = evm_addr.keys().collect::<Vec<_>>();
                let evm_addr_json = serde_json::to_string(evm_addr).unwrap_or_else(|_| "failed to serialize".to_string());
                tracing::error!(
                    "connected_chain_evm_address 'vec' field not found for solver '{}'. EVM address object keys: {:?}, Full object: {}",
                    solver_address,
                    evm_addr_keys,
                    evm_addr_json
                );
                return Ok(None);
            }
        };

        // Parse EVM address bytes (handles both array and hex string formats)
        let evm_bytes = match Self::parse_evm_address_bytes(vec_array, solver_address)? {
            Some(bytes) => bytes,
            None => return Ok(None),
        };

        // Convert bytes to hex string with 0x prefix
        let hex_string = format!("0x{}", evm_bytes.iter().map(|b| format!("{:02x}", b)).collect::<String>());

        tracing::error!(
            "DEBUG: Successfully extracted EVM address for solver '{}': {}",
            solver_address,
            hex_string
        );

        Ok(Some(hex_string))
    }

    /// Find the SolverRegistry resource from the resources list.
    ///
    /// Handles both resource type formats (with and without 0x prefix).
    fn find_solver_registry_resource<'a>(
        resources: &'a [ResourceData],
        registry_address: &str,
    ) -> Option<&'a ResourceData> {
        let registry_addr_normalized = registry_address
            .strip_prefix("0x")
            .unwrap_or(registry_address);
        
        let registry_resource_type_with_prefix =
            format!("0x{}::solver_registry::SolverRegistry", registry_addr_normalized);
        let registry_resource_type_without_prefix =
            format!("{}::solver_registry::SolverRegistry", registry_addr_normalized);

        let resource = resources
            .iter()
            .find(|r| {
                r.resource_type == registry_resource_type_with_prefix
                    || r.resource_type == registry_resource_type_without_prefix
            });

        if resource.is_none() {
            tracing::warn!(
                "SolverRegistry resource not found. Registry address: {}, Tried types: '{}' and '{}', Available resources: {:?}",
                registry_address,
                registry_resource_type_with_prefix,
                registry_resource_type_without_prefix,
                resources.iter().map(|r| &r.resource_type).collect::<Vec<_>>()
            );
        }

        resource
    }

    /// Extract the solvers data array from the SolverRegistry resource.
    ///
    /// SimpleMap<address, SolverInfo> is serialized as {"data": [{"key": address, "value": SolverInfo}, ...]}
    fn extract_solvers_data_array(
        registry_resource: &ResourceData,
    ) -> Option<&serde_json::Value> {
        let data = registry_resource.data.as_object()?;
        let solvers = data.get("solvers")?.as_object()?;
        solvers.get("data")
    }

    /// Find the solver entry in the data array by matching normalized addresses.
    fn find_solver_entry<'a>(
        data_array: &'a serde_json::Value,
        solver_address: &str,
        solver_addr_normalized: &str,
    ) -> Option<&'a serde_json::Map<String, serde_json::Value>> {
        let data_array = data_array.as_array()?;
        
        // Log all available solver keys with their normalized forms
        let available_solvers_debug: Vec<(String, String)> = data_array
            .iter()
            .filter_map(|entry| {
                let entry_obj = entry.as_object()?;
                let key = entry_obj.get("key")?.as_str()?;
                let key_normalized = key.strip_prefix("0x").unwrap_or(key).to_lowercase();
                Some((key.to_string(), key_normalized))
            })
            .collect();
        
        tracing::error!(
            "DEBUG: Looking for solver in registry. Input solver_address='{}' (type: str), normalized='{}' (type: str, len: {}), Available solvers (original -> normalized): {:?}",
            solver_address,
            solver_addr_normalized,
            solver_addr_normalized.len(),
            available_solvers_debug
        );
        
        let solver_entry = data_array.iter().find_map(|entry| {
            let entry_obj = entry.as_object()?;
            let key = entry_obj.get("key")?.as_str()?;
            let key_normalized = key.strip_prefix("0x").unwrap_or(key).to_lowercase();
            
            tracing::error!(
                "DEBUG: Comparing - Looking for: '{}' (normalized: '{}', len: {}) vs Registry key: '{}' (normalized: '{}', len: {}) -> Match: {}",
                solver_address,
                solver_addr_normalized,
                solver_addr_normalized.len(),
                key,
                key_normalized,
                key_normalized.len(),
                key_normalized == solver_addr_normalized
            );
            
            (key_normalized == solver_addr_normalized).then_some(entry_obj)
        });

        if solver_entry.is_none() {
            tracing::error!(
                "Solver not found in registry. Looking for: '{}' (normalized: '{}', len: {}), Available solvers (original -> normalized): {:?}",
                solver_address,
                solver_addr_normalized,
                solver_addr_normalized.len(),
                available_solvers_debug
            );
        }

        solver_entry
    }

    /// Parse EVM address bytes from Option<vector<u8>> serialization.
    ///
    /// # Important
    ///
    /// Aptos can serialize Option<vector<u8>> in two different formats:
    /// 1. Array format: {"vec": [bytes_array]} where bytes_array is [u64, u64, ...]
    ///    Example: {"vec": [[60, 68, 205, 221, ...]]}
    /// 2. Hex string format: {"vec": ["0xhexstring"]} where the hex string is the address
    ///    Example: {"vec": ["0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc"]}
    ///
    /// This inconsistency in Aptos serialization caused EVM outflow validation to fail
    /// when addresses were returned as hex strings. We now handle both formats.
    fn parse_evm_address_bytes(
        vec_array: &serde_json::Value,
        solver_address: &str,
    ) -> Result<Option<Vec<u8>>> {
        let vec_array = vec_array.as_array().ok_or_else(|| {
            anyhow::anyhow!("vec field is not an array")
        })?;

        if vec_array.is_empty() {
            tracing::debug!(
                "Solver '{}' found but connected_chain_evm_address vec is empty (None)",
                solver_address
            );
            return Ok(None);
        }

        tracing::error!(
            "DEBUG: connected_chain_evm_address vec for solver '{}': length={}, vec[0]={}",
            solver_address,
            vec_array.len(),
            serde_json::to_string(vec_array.get(0).unwrap_or(&serde_json::Value::Null)).unwrap_or_else(|_| "failed to serialize".to_string())
        );

        let evm_bytes_opt = vec_array.get(0);
        
        let evm_bytes: Vec<u8> = if let Some(bytes_val) = evm_bytes_opt {
            // Try to parse as array of u64 (most common case for Move vector<u8>)
            if let Some(bytes_array) = bytes_val.as_array() {
                let mut result = Vec::new();
                for byte_val in bytes_array {
                    if let Some(byte) = byte_val.as_u64() {
                        if byte > 255 {
                            tracing::error!(
                                "Invalid byte value {} (>255) in EVM address for solver '{}'",
                                byte,
                                solver_address
                            );
                            return Ok(None);
                        }
                        result.push(byte as u8);
                    } else {
                        let vec0_json = serde_json::to_string(byte_val).unwrap_or_else(|_| "failed to serialize".to_string());
                        tracing::error!(
                            "Non-u64 value in EVM address bytes array for solver '{}': {}",
                            solver_address,
                            vec0_json
                        );
                        return Ok(None);
                    }
                }
                result
            } else if let Some(hex_str) = bytes_val.as_str() {
                // Try to parse as hex string (e.g., "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc")
                let hex_clean = hex_str.strip_prefix("0x").unwrap_or(hex_str);
                if hex_clean.len() % 2 != 0 {
                    tracing::error!(
                        "Invalid hex string length {} in EVM address for solver '{}'",
                        hex_clean.len(),
                        solver_address
                    );
                    return Ok(None);
                }
                (0..hex_clean.len())
                    .step_by(2)
                    .filter_map(|i| u8::from_str_radix(&hex_clean[i..i + 2], 16).ok())
                    .collect()
            } else {
                let vec0_json = serde_json::to_string(bytes_val).unwrap_or_else(|_| "failed to serialize".to_string());
                tracing::error!(
                    "connected_chain_evm_address vec[0] is neither an array nor a string for solver '{}'. vec[0] value: {}",
                    solver_address,
                    vec0_json
                );
                return Ok(None);
            }
        } else {
            tracing::error!(
                "connected_chain_evm_address vec is non-empty but vec[0] is missing for solver '{}'",
                solver_address
            );
            return Ok(None);
        };

        if evm_bytes.is_empty() {
            tracing::error!(
                "Solver '{}' found but connected_chain_evm_address bytes array is empty",
                solver_address
            );
            return Ok(None);
        }

        if evm_bytes.len() != 20 {
            tracing::error!(
                "Solver '{}' found but connected_chain_evm_address has invalid length {} (expected 20 bytes for EVM address)",
                solver_address,
                evm_bytes.len()
            );
            return Ok(None);
        }

        tracing::error!(
            "DEBUG: Successfully parsed EVM address bytes for solver '{}': length={}, first 5 bytes: {:?}",
            solver_address,
            evm_bytes.len(),
            evm_bytes.iter().take(5).copied().collect::<Vec<_>>()
        );

        Ok(Some(evm_bytes))
    }

    /// Calls a view function on the Move VM blockchain.
    ///
    /// # Arguments
    ///
    /// * `module_address` - Address of the module
    /// * `module_name` - Name of the module
    /// * `function_name` - Name of the function
    /// * `type_args` - Type arguments (if any)
    /// * `args` - Function arguments
    ///
    /// # Returns
    ///
    /// * `Ok(serde_json::Value)` - Function return value
    /// * `Err(anyhow::Error)` - Failed to call view function
    pub async fn call_view_function(
        &self,
        module_address: &str,
        module_name: &str,
        function_name: &str,
        type_args: Vec<String>,
        args: Vec<serde_json::Value>,
    ) -> Result<serde_json::Value> {
        let url = format!("{}/v1/view", self.base_url);

        let request_body = serde_json::json!({
            "function": format!("{}::{}::{}", module_address, module_name, function_name),
            "type_arguments": type_args,
            "arguments": args,
        });

        let response = self
            .client
            .post(&url)
            .json(&request_body)
            .send()
            .await
            .context("Failed to send view function request")?
            .error_for_status()
            .context("View function request failed")?;

        let result: serde_json::Value = response
            .json()
            .await
            .context("Failed to parse view function response")?;

        Ok(result)
    }
}

// ============================================================================
// EVENT DATA STRUCTURES FOR MOVE EVENTS
// ============================================================================

/// Represents a LimitOrderEvent emitted by the Move fa_intent module
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LimitOrderEvent {
    pub intent_address: String,
    pub intent_id: String,                   // For cross-chain linking
    pub offered_metadata: serde_json::Value, // Can be Object<Metadata> which is {"inner":"0x..."}
    pub offered_amount: String,
    pub offered_chain_id: String,
    pub desired_metadata: serde_json::Value, // Can be Object<Metadata> which is {"inner":"0x..."}
    pub desired_amount: String,
    pub desired_chain_id: String,
    pub requester: String,
    pub expiry_time: String,
    pub revocable: bool,
}

/// Represents an OracleLimitOrderEvent emitted by the Move fa_intent_with_oracle module
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OracleLimitOrderEvent {
    pub intent_address: String, // The escrow intent address (on connected chain)
    pub intent_id: String,      // The original intent ID (from hub chain)
    pub offered_metadata: serde_json::Value, // Can be Object<Metadata> which is {"inner":"0x..."}
    pub offered_amount: String,
    #[serde(deserialize_with = "deserialize_u64_string")]
    pub offered_chain_id: String, // Chain ID where offered tokens are located
    pub desired_metadata: serde_json::Value, // Can be Object<Metadata> which is {"inner":"0x..."}
    pub desired_amount: String,
    #[serde(deserialize_with = "deserialize_u64_string")]
    pub desired_chain_id: String, // Chain ID where desired tokens are located
    pub requester: String,
    pub expiry_time: String,
    pub min_reported_value: String,
    pub revocable: bool,
    #[serde(
        deserialize_with = "deserialize_move_option_string",
        skip_serializing_if = "Option::is_none"
    )]
    pub reserved_solver: Option<String>, // Solver address if the intent is reserved (None for unreserved intents)
    #[serde(
        deserialize_with = "deserialize_move_option_string",
        skip_serializing_if = "Option::is_none"
    )]
    pub requester_address_connected_chain: Option<String>, // Requester address on connected chain (for outflow intents)
}

/// Represents a LimitOrderFulfillmentEvent emitted when an intent is fulfilled
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LimitOrderFulfillmentEvent {
    pub intent_address: String,
    pub intent_id: String,
    pub solver: String,
    pub provided_metadata: serde_json::Value,
    pub provided_amount: String,
    pub timestamp: String,
}

#[cfg(test)]
mod tests {
    // Tests will be added in integration tests or separate test file
}

