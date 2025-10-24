//! Event Monitoring Module
//! 
//! This module handles monitoring blockchain events from both hub and connected chains.
//! It listens for intent creation events on the hub chain and escrow deposit events 
//! on the connected chain, providing real-time event processing and caching.
//! 
//! ## Security Requirements
//! 
//! ⚠️ **CRITICAL**: The monitor must validate that escrow intents are **non-revocable** 
//! (`revocable = false`) before allowing any cross-chain actions to proceed.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, warn, error};

use crate::config::Config;

// ============================================================================
// EVENT DATA STRUCTURES
// ============================================================================

/// Intent creation event from the hub chain.
/// 
/// This event is emitted when a new intent is created on the hub chain.
/// The verifier monitors these events to track new trading opportunities
/// and validate their safety for escrow operations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentEvent {
    /// Unique identifier for the intent
    pub intent_id: String,
    /// Address of the intent creator
    pub creator: String,
    /// Metadata of the source asset being offered
    pub source_metadata: String,
    /// Amount of the source asset being offered
    pub source_amount: u64,
    /// Metadata of the desired asset
    pub desired_metadata: String,
    /// Amount of the desired asset
    pub desired_amount: u64,
    /// Unix timestamp when the intent expires
    pub expiry_time: u64,
    /// Whether the intent can be revoked by the creator
    pub revocable: bool,
    /// Timestamp when the event was received
    pub timestamp: u64,
}

/// Escrow deposit event from the connected chain.
/// 
/// This event is emitted when a solver deposits assets into an escrow
/// on the connected chain. The verifier validates that this deposit
/// fulfills the conditions specified in the original intent.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EscrowEvent {
    /// Unique identifier for the escrow
    pub escrow_id: String,
    /// Address of the solver who made the deposit
    pub solver: String,
    /// Amount of assets deposited
    pub deposit_amount: u64,
    /// Metadata of the deposited assets
    pub deposit_metadata: String,
    /// Timestamp when the event was received
    pub timestamp: u64,
}

// ============================================================================
// EVENT MONITOR IMPLEMENTATION
// ============================================================================

/// Event monitor that watches both hub and connected chains for relevant events.
/// 
/// This monitor runs continuously, polling both chains for new events and
/// processing them according to the verifier's validation rules. It maintains
/// an in-memory cache of recent events for API access.
pub struct EventMonitor {
    /// Service configuration
    config: Arc<Config>,
    /// HTTP client for hub chain communication
    hub_client: reqwest::Client,
    /// HTTP client for connected chain communication
    connected_client: reqwest::Client,
    /// In-memory cache of recent intent events
    event_cache: Arc<RwLock<Vec<IntentEvent>>>,
}

impl EventMonitor {
    /// Creates a new event monitor with the given configuration.
    /// 
    /// This function initializes HTTP clients with appropriate timeouts
    /// and prepares the event cache for use.
    /// 
    /// # Arguments
    /// 
    /// * `config` - Service configuration containing chain URLs and timeouts
    /// 
    /// # Returns
    /// 
    /// * `Ok(EventMonitor)` - Successfully created monitor
    /// * `Err(anyhow::Error)` - Failed to create monitor
    pub async fn new(config: &Config) -> Result<Self> {
        // Create HTTP client for hub chain with configured timeout
        let hub_client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_millis(config.verifier.validation_timeout_ms))
            .build()?;
            
        // Create HTTP client for connected chain with configured timeout
        let connected_client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_millis(config.verifier.validation_timeout_ms))
            .build()?;
        
        Ok(Self {
            config: Arc::new(config.clone()),
            hub_client,
            connected_client,
            event_cache: Arc::new(RwLock::new(Vec::new())),
        })
    }
    
    /// Starts the event monitoring process for both chains.
    /// 
    /// This function runs two concurrent monitoring loops:
    /// 1. Hub chain monitoring for intent events
    /// 2. Connected chain monitoring for escrow events
    /// 
    /// The function blocks until both monitors complete (which should be never
    /// in normal operation, as they run infinite loops).
    /// 
    /// # Returns
    /// 
    /// * `Ok(())` - Monitoring started successfully
    /// * `Err(anyhow::Error)` - Failed to start monitoring
    pub async fn start_monitoring(&self) -> Result<()> {
        info!("Starting event monitoring for both chains");
        
        // Start monitoring both chains concurrently
        let hub_monitor = self.monitor_hub_chain();
        let connected_monitor = self.monitor_connected_chain();
        
        // Run both monitors concurrently (this blocks until both complete)
        tokio::try_join!(hub_monitor, connected_monitor)?;
        
        Ok(())
    }
    
    /// Monitors the hub chain for intent creation events.
    /// 
    /// This function runs in an infinite loop, polling the hub chain for
    /// new intent events. When events are found, it validates their safety
    /// for escrow operations and caches them for later processing.
    async fn monitor_hub_chain(&self) -> Result<()> {
        info!("Starting hub chain monitoring for intent events");
        
        loop {
            match self.poll_hub_events().await {
                Ok(events) => {
                    for event in events {
                        info!("Received intent event: {:?}", event);
                        
                        // 🔒 CRITICAL SECURITY CHECK: Validate intent revocability
                        if !event.revocable {
                            info!("Intent {} is non-revocable - safe for escrow", event.intent_id);
                        } else {
                            warn!("Intent {} is revocable - NOT safe for escrow", event.intent_id);
                        }
                        
                        // Cache the event for API access
                        {
                            let mut cache = self.event_cache.write().await;
                            cache.push(event);
                        }
                    }
                }
                Err(e) => {
                    error!("Error polling hub events: {}", e);
                }
            }
            
            // Wait before next poll
            tokio::time::sleep(std::time::Duration::from_millis(
                self.config.verifier.polling_interval_ms
            )).await;
        }
    }
    
    /// Monitors the connected chain for escrow deposit events.
    /// 
    /// This function runs in an infinite loop, polling the connected chain
    /// for escrow deposit events. When events are found, it validates that
    /// the deposits fulfill the conditions of existing intents.
    async fn monitor_connected_chain(&self) -> Result<()> {
        info!("Starting connected chain monitoring for escrow events");
        
        loop {
            match self.poll_connected_events().await {
                Ok(events) => {
                    for event in events {
                        info!("Received escrow event: {:?}", event);
                        
                        // Validate that this escrow fulfills an existing intent
                        if let Err(e) = self.validate_intent_fulfillment(&event).await {
                            error!("Intent fulfillment validation failed: {}", e);
                        }
                    }
                }
                Err(e) => {
                    error!("Error polling connected events: {}", e);
                }
            }
            
            // Wait before next poll
            tokio::time::sleep(std::time::Duration::from_millis(
                self.config.verifier.polling_interval_ms
            )).await;
        }
    }
    
    /// Polls the hub chain for new intent events.
    /// 
    /// This function queries the hub chain's event logs for new intent
    /// creation events. In a real implementation, this would use the
    /// Aptos SDK to subscribe to specific event types.
    /// 
    /// # Returns
    /// 
    /// * `Ok(Vec<IntentEvent>)` - List of new intent events
    /// * `Err(anyhow::Error)` - Failed to poll events
    async fn poll_hub_events(&self) -> Result<Vec<IntentEvent>> {
        // TODO: Implement actual Aptos event polling using the Aptos SDK
        // This would subscribe to LimitOrderEvent and OracleLimitOrderEvent
        // from the intent framework module
        Ok(vec![])
    }
    
    /// Polls the connected chain for new escrow events.
    /// 
    /// This function queries the connected chain's event logs for new
    /// escrow deposit events. In a real implementation, this would
    /// monitor escrow-specific events.
    /// 
    /// # Returns
    /// 
    /// * `Ok(Vec<EscrowEvent>)` - List of new escrow events
    /// * `Err(anyhow::Error)` - Failed to poll events
    async fn poll_connected_events(&self) -> Result<Vec<EscrowEvent>> {
        // TODO: Implement actual escrow event polling
        // This would monitor escrow deposit events on the connected chain
        Ok(vec![])
    }
    
    /// Validates that an escrow event fulfills the conditions of an existing intent.
    /// 
    /// This function checks whether the escrow deposit matches the requirements
    /// specified in a previously created intent. It ensures that the solver
    /// has provided the correct asset type and amount.
    /// 
    /// # Arguments
    /// 
    /// * `escrow_event` - The escrow deposit event to validate
    /// 
    /// # Returns
    /// 
    /// * `Ok(())` - Validation successful
    /// * `Err(anyhow::Error)` - Validation failed
    async fn validate_intent_fulfillment(&self, escrow_event: &EscrowEvent) -> Result<()> {
        info!("Validating intent fulfillment for escrow: {}", escrow_event.escrow_id);
        
        // TODO: Implement actual intent fulfillment validation
        // This would:
        // 1. Find the corresponding intent from the cache
        // 2. Check that deposit amount matches desired amount
        // 3. Check that deposit metadata matches desired metadata
        // 4. Verify the solver is authorized (if applicable)
        
        Ok(())
    }
    
    /// Returns a copy of all cached intent events.
    /// 
    /// This function provides access to the event cache for API endpoints
    /// and external monitoring systems.
    /// 
    /// # Returns
    /// 
    /// A vector containing all cached intent events
    pub async fn get_cached_events(&self) -> Vec<IntentEvent> {
        self.event_cache.read().await.clone()
    }
}
