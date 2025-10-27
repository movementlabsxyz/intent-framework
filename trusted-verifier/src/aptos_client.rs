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
    pub inner: T,
}

/// Account information from Aptos
#[derive(Debug, Deserialize)]
pub struct AccountInfo {
    pub sequence_number: String,
    pub authentication_key: String,
}

/// Event from Aptos blockchain
#[derive(Debug, Deserialize, Clone)]
pub struct AptosEvent {
    pub key: String,
    pub sequence_number: String,
    pub r#type: String,
    pub data: serde_json::Value,
}

/// Transaction details from Aptos
#[derive(Debug, Deserialize)]
pub struct TransactionInfo {
    pub version: String,
    pub hash: String,
    pub success: bool,
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
    /// # Arguments
    ///
    /// * `address` - Account address to query events for
    /// * `event_handle` - Optional event handle to filter by
    /// * `start` - Starting sequence number (optional)
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
        let mut url = format!("{}/v1/accounts/{}/events", self.base_url, address);

        if let Some(handle) = event_handle {
            url.push_str(&format!("/{}", handle));
        }

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
            .context("Failed to send events request")?
            .error_for_status()
            .context("Events request failed")?;

        let events: Vec<AptosEvent> = response.json().await
            .context("Failed to parse events response")?;

        Ok(events)
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
    pub fn base_url(&self) -> &str {
        &self.base_url
    }
}

#[cfg(test)]
mod tests {
    // Tests will be added in integration tests or separate test file
}

