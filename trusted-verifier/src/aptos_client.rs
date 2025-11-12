//! Aptos REST Client Module
//!
//! This module provides a client for communicating with Aptos blockchain nodes
//! via their HTTP REST API. It handles account queries, event polling, and
//! transaction verification.
//!
//! ## Features
//!
//! - Query account information
//! - Poll for events on specific accounts
//! - Get transaction details
//! - Parse and handle Aptos REST API responses

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;

// ============================================================================
// API RESPONSE STRUCTURES
// ============================================================================

/// Aptos REST API response wrapper
#[derive(Debug, Deserialize)]
pub struct AptosResponse<T> {
    #[allow(dead_code)]
    pub inner: T,
}

/// Account information from Aptos
#[derive(Debug, Deserialize)]
pub struct AccountInfo {
    #[allow(dead_code)]
    pub sequence_number: String,
    #[allow(dead_code)]
    pub authentication_key: String,
}

/// Resource data from Aptos account
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

/// Event from Aptos blockchain
/// Can be either a module event (with guid) or legacy EventHandle event (with key)
#[derive(Debug, Deserialize, Clone)]
pub struct AptosEvent {
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

/// Transaction details from Aptos
#[derive(Debug, Deserialize)]
pub struct TransactionInfo {
    #[allow(dead_code)]
    pub version: String,
    #[allow(dead_code)]
    pub hash: String,
    #[allow(dead_code)]
    pub success: bool,
    #[allow(dead_code)]
    pub events: Vec<AptosEvent>,
}

// ============================================================================
// APTOS CLIENT IMPLEMENTATION
// ============================================================================

/// Client for communicating with Aptos blockchain nodes via REST API
pub struct AptosClient {
    /// HTTP client for making requests
    client: Client,
    /// Base URL of the Aptos node (e.g., "http://127.0.0.1:8080")
    base_url: String,
}

impl AptosClient {
    /// Creates a new Aptos client for the given node URL
    ///
    /// # Arguments
    ///
    /// * `node_url` - Base URL of the Aptos node (e.g., "http://127.0.0.1:8080")
    ///
    /// # Returns
    ///
    /// * `Ok(AptosClient)` - Successfully created client
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

    /// Queries account information from the Aptos blockchain
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
        
        let response = self.client
            .get(&url)
            .send()
            .await
            .context("Failed to send account request")?
            .error_for_status()
            .context("Account request failed")?;

        let account: AccountInfo = response.json().await
            .context("Failed to parse account response")?;

        Ok(account)
    }

    /// Queries events for a specific account on the Aptos blockchain
    ///
    /// This method queries module events by scanning transaction history.
    /// For modern Aptos modules that use `event::emit()`, events are stored
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
    /// However, Aptos has **deprecated EventHandle in favor of module events**.
    /// See: https://aptos.guide/network/blockchain/events
    ///
    /// **Current approach**: Query known user accounts' transaction history to extract
    /// module events. This is suitable for our test scenario with Alice/Bob accounts.
    /// For production, consider using the Aptos Indexer GraphQL API for more efficient
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
    /// * `Ok(Vec<AptosEvent>)` - List of events
    /// * `Err(anyhow::Error)` - Failed to query events
    pub async fn get_account_events(
        &self,
        address: &str,
        event_handle: Option<&str>,
        start: Option<u64>,
        limit: Option<u64>,
    ) -> Result<Vec<AptosEvent>> {
        // For legacy EventHandle events, use the old approach
        if let Some(handle) = event_handle {
            return self.get_events_by_creation_number(address, handle, start, limit).await;
        }

        // For modern module events, query the account's transactions to find events
        // This is necessary because module events are emitted in user transactions, not on module account
        let limit = limit.unwrap_or(100);
        let url = format!("{}/v1/accounts/{}/transactions", self.base_url, address);
        
        let response = self.client
            .get(&url)
            .query(&[("limit", limit.to_string())])
            .send()
            .await
            .context("Failed to query account transactions")?;

        if !response.status().is_success() {
            return Ok(vec![]); // Account might not exist or have no transactions
        }

        let transactions: Vec<serde_json::Value> = response.json().await
            .context("Failed to parse transactions response")?;

        // Extract events from transactions
        let mut events = Vec::new();
        for tx in transactions {
            if let Some(tx_events) = tx.get("events").and_then(|e| e.as_array()) {
                for event_json in tx_events {
                    // Extract event fields manually to handle different formats
                    let event_type = event_json.get("type").and_then(|t| t.as_str())
                        .unwrap_or("").to_string();
                    let event_data = event_json.get("data").cloned()
                        .unwrap_or(serde_json::Value::Null);
                    
                    // Extract sequence number
                    let sequence_number = event_json.get("sequence_number")
                        .and_then(|s| s.as_str())
                        .unwrap_or("0").to_string();
                    
                    // Extract guid if present (for module events)
                    let guid = event_json.get("guid").and_then(|g| serde_json::from_value::<EventGuid>(g.clone()).ok());
                    
                    // Extract key if present (for EventHandle events)
                    let key = event_json.get("key").and_then(|k| k.as_str()).map(|s| s.to_string());
                    
                    events.push(AptosEvent {
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
    /// * `Ok(Vec<AptosEvent>)` - List of events
    /// * `Err(anyhow::Error)` - Failed to query events
    async fn get_events_by_creation_number(
        &self,
        address: &str,
        creation_number: &str,
        start: Option<u64>,
        limit: Option<u64>,
    ) -> Result<Vec<AptosEvent>> {
        let mut url = format!("{}/v1/accounts/{}/events/{}", self.base_url, address, creation_number);

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

        let response = self.client
            .get(&url)
            .send()
            .await
            .context("Failed to send events request")?;
        
        // If 404, return empty vec (no events yet)
        let status = response.status();
        if status == 404 {
            return Ok(vec![]);
        }
        
        let response = response.error_for_status()
            .context("Events request failed")?;

        let events: Vec<AptosEvent> = response.json().await
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
        
        let response = self.client
            .get(&url)
            .send()
            .await
            .context("Failed to send resources request")?
            .error_for_status()
            .context("Resources request failed")?;

        let resources: Vec<ResourceData> = response.json().await
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
    /// 2. It's not the official Aptos API pattern for event monitoring
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
    pub async fn find_event_handles(&self, address: &str, event_type_pattern: &str) -> Result<Vec<String>> {
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
                            if let Ok(handle) = serde_json::from_value::<EventHandle>(value.clone()) {
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
    /// * `Ok(TransactionInfo)` - Transaction information
    /// * `Err(anyhow::Error)` - Failed to query transaction
    #[allow(dead_code)]
    pub async fn get_transaction(&self, hash: &str) -> Result<TransactionInfo> {
        let url = format!("{}/v1/transactions/by_hash/{}", self.base_url, hash);
        
        let response = self.client
            .get(&url)
            .send()
            .await
            .context("Failed to send transaction request")?
            .error_for_status()
            .context("Transaction request failed")?;

        let tx: TransactionInfo = response.json().await
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
        
        let response = self.client
            .get(&url)
            .send()
            .await
            .context("Failed to send health check request")?
            .error_for_status()
            .context("Health check failed")?;

        // Just check if we got a response
        response.text().await
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
    pub async fn get_intent_solver(&self, intent_address: &str, _module_address: &str) -> Result<Option<String>> {
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

    /// Queries the solver registry to get a solver's EVM address.
    ///
    /// # Arguments
    ///
    /// * `solver_address` - Aptos address of the solver
    /// * `registry_address` - Address where the solver registry is deployed (usually @mvmt_intent)
    ///
    /// # Returns
    ///
    /// * `Ok(Option<String>)` - EVM address if solver is registered, None otherwise
    /// * `Err(anyhow::Error)` - Failed to query registry
    pub async fn get_solver_evm_address(&self, solver_address: &str, registry_address: &str) -> Result<Option<String>> {
        // Use view function to call solver_registry::get_evm_address
        let result = self.call_view_function(
            registry_address,
            "solver_registry",
            "get_evm_address",
            vec![],
            vec![serde_json::json!(solver_address)],
        ).await;
        
        match result {
            Ok(value) => {
                // The view function returns a vector<u8> (empty if not registered)
                if let Some(evm_bytes) = value.as_array() {
                    if evm_bytes.is_empty() {
                        Ok(None)
                    } else {
                        // Convert vector<u8> to hex string with 0x prefix
                        let mut hex_string = String::from("0x");
                        for byte_val in evm_bytes {
                            if let Some(byte) = byte_val.as_u64() {
                                hex_string.push_str(&format!("{:02x}", byte as u8));
                            }
                        }
                        Ok(Some(hex_string))
                    }
                } else {
                    Ok(None)
                }
            }
            Err(e) => {
                // If view function fails, solver might not be registered
                // Log and return None
                tracing::debug!("Failed to query solver EVM address: {}", e);
                Ok(None)
            }
        }
    }

    /// Calls a view function on the Aptos blockchain.
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
        
        let response = self.client
            .post(&url)
            .json(&request_body)
            .send()
            .await
            .context("Failed to send view function request")?
            .error_for_status()
            .context("View function request failed")?;

        let result: serde_json::Value = response.json().await
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
    pub intent_id: String,  // For cross-chain linking
    pub source_metadata: serde_json::Value, // Can be Object<Metadata> which is {"inner":"0x..."}
    pub source_amount: String,
    pub desired_metadata: serde_json::Value, // Can be Object<Metadata> which is {"inner":"0x..."}
    pub desired_amount: String,
    pub issuer: String,
    pub expiry_time: String,
    pub revocable: bool,
    #[serde(default, deserialize_with = "deserialize_optional_chain_id")]
    pub connected_chain_id: Option<String>, // Optional chain ID where escrow will be created (None for regular intents)
}

/// Custom deserializer for connected_chain_id that handles Move Option<u64> format
/// Move Option<T> is serialized as {"vec": [value]} for Some(value) or {"vec": []} for None
fn deserialize_optional_chain_id<'de, D>(deserializer: D) -> Result<Option<String>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    use serde::Deserialize;
    let value: serde_json::Value = serde_json::Value::deserialize(deserializer)?;
    
    // Handle Move Option format: {"vec": [value]} or {"vec": []}
    if let serde_json::Value::Object(map) = &value {
        if let Some(serde_json::Value::Array(vec)) = map.get("vec") {
            if vec.is_empty() {
                return Ok(None);
            }
            if let Some(first) = vec.first() {
                match first {
                    serde_json::Value::Number(n) => return Ok(Some(n.to_string())),
                    serde_json::Value::String(s) => return Ok(Some(s.clone())),
                    _ => {}
                }
            }
        }
    }
    
    // Fallback: handle direct Option format (null, number, or string)
    match value {
        serde_json::Value::Null => Ok(None),
        serde_json::Value::Number(n) => Ok(Some(n.to_string())),
        serde_json::Value::String(s) => Ok(Some(s)),
        _ => Ok(None), // Ignore other types
    }
}

/// Represents an OracleLimitOrderEvent emitted by the Move fa_intent_with_oracle module
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OracleLimitOrderEvent {
    pub intent_address: String,      // The escrow intent address (on connected chain)
    pub intent_id: String,            // The original intent ID (from hub chain)
    pub source_metadata: serde_json::Value, // Can be Object<Metadata> which is {"inner":"0x..."}
    pub source_amount: String,
    pub desired_metadata: serde_json::Value, // Can be Object<Metadata> which is {"inner":"0x..."}
    pub desired_amount: String,
    pub issuer: String,
    pub expiry_time: String,
    pub min_reported_value: String,
    pub revocable: bool,
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

