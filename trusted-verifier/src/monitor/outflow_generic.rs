//! Outflow-specific monitor helpers (chain-agnostic)
//!
//! Handles hub chain intent monitoring for outflow intents.
//! Outflow intents have tokens locked on the hub chain and request tokens on the connected chain.

use anyhow::Result;
use tracing::{error, info};

use super::generic::{EventMonitor, FulfillmentEvent, IntentEvent};
use super::hub_mvm;

// ============================================================================
// HUB CHAIN MONITORING
// ============================================================================

/// Monitors the hub chain for intent creation events.
///
/// This function runs in an infinite loop, polling the hub chain for
/// new intent events. When events are found, it validates their safety
/// for escrow operations and caches them for later processing.
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
///
/// # Returns
///
/// * `Ok(())` - Monitoring started successfully (runs indefinitely)
/// * `Err(anyhow::Error)` - Failed to start monitoring
pub async fn monitor_hub_chain(monitor: &EventMonitor) -> Result<()> {
    info!("Starting hub chain monitoring for intent events");

    loop {
        match poll_hub_events(monitor).await {
            Ok(events) => {
                for event in events {
                    info!("Received intent event: {:?}", event);

                    // CRITICAL SECURITY CHECK: Reject revocable intents
                    if event.revocable {
                        error!("SECURITY: Rejecting revocable intent {} from {} - NOT safe for escrow", event.intent_id, event.requester);
                        continue; // Skip this event - do not cache or process
                    }

                    info!(
                        "Request-intent {} is non-revocable - safe for escrow",
                        event.intent_id
                    );

                    // Cache the event for API access (only non-revocable events)
                    {
                        let intent_id = event.intent_id.clone();
                        let mut cache = monitor.event_cache.write().await;
                        // Check if this intent_id already exists in the cache (normalize for comparison)
                        let normalized_intent_id =
                            crate::monitor::generic::normalize_intent_id(&intent_id);
                        if !cache.iter().any(|cached| {
                            crate::monitor::generic::normalize_intent_id(&cached.intent_id)
                                == normalized_intent_id
                        }) {
                            cache.push(event);
                        }
                    }
                }
            }
            Err(e) => {
                error!("Error polling hub events: {}", e);
            }
        }

        // Wait before next poll
        tokio::time::sleep(std::time::Duration::from_millis(
            monitor.config.verifier.polling_interval_ms,
        ))
        .await;
    }
}

/// Polls the hub chain for new intent events.
///
/// This function queries the hub chain's event logs for new intent
/// creation events. It delegates to chain-specific polling functions.
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
///
/// # Returns
///
/// * `Ok(Vec<IntentEvent>)` - List of new intent events
/// * `Err(anyhow::Error)` - Failed to poll events
///
/// # Note
///
/// Currently, the hub chain is always Move VM. This function delegates to
/// hub_mvm::poll_hub_events for Move VM-specific polling logic.
pub async fn poll_hub_events(monitor: &EventMonitor) -> Result<Vec<IntentEvent>> {
    // Hub chain is currently always Move VM
    // Delegate to Move VM-specific polling
    hub_mvm::poll_hub_events(monitor).await
}

// ============================================================================
// CACHE ACCESS
// ============================================================================

/// Returns a copy of all cached intent events.
///
/// This function provides access to the event cache for API endpoints
/// and external monitoring systems.
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
///
/// # Returns
///
/// A vector containing all cached intent events
pub async fn get_cached_events(monitor: &EventMonitor) -> Vec<IntentEvent> {
    monitor.event_cache.read().await.clone()
}

/// Returns a copy of all cached fulfillment events.
///
/// This function provides access to the fulfillment event cache for API endpoints.
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
///
/// # Returns
///
/// A vector containing all cached fulfillment events
pub async fn get_cached_fulfillment_events(monitor: &EventMonitor) -> Vec<FulfillmentEvent> {
    monitor.fulfillment_cache.read().await.clone()
}
