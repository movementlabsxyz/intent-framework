//! Outflow Move VM-specific monitoring functions
//!
//! This module contains Move VM-specific event polling logic
//! for hub chain request intent events on Move VM chains.

use anyhow::{Result, Context};
use tracing::{info, error};

use crate::mvm_client::{MvmClient, OracleLimitOrderEvent as MvmOracleLimitOrderEvent, LimitOrderFulfillmentEvent as MvmLimitOrderFulfillmentEvent};
use crate::monitor::generic::{EventMonitor, RequestIntentEvent, FulfillmentEvent};
use crate::monitor::inflow_generic;

/// Polls the hub Move VM chain for new request intent events.
/// 
/// This function queries the hub chain's event logs for new request intent
/// creation events. Since module events are emitted in user transactions,
/// we query known test accounts for their events.
/// 
/// # Arguments
/// 
/// * `monitor` - The event monitor instance
/// 
/// # Returns
/// 
/// * `Ok(Vec<RequestIntentEvent>)` - List of new request intent events
/// * `Err(anyhow::Error)` - Failed to poll events
pub async fn poll_hub_events(monitor: &EventMonitor) -> Result<Vec<RequestIntentEvent>> {
    // Create Move VM client for hub chain
    let client = MvmClient::new(&monitor.config.hub_chain.rpc_url)?;
        
    // Query events from known test accounts
    let known_accounts = monitor.config.hub_chain.known_accounts.as_ref()
        .ok_or_else(|| anyhow::anyhow!("No known accounts configured for hub chain"))?;
    
    let mut intent_events = Vec::new();
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs();
    
    // Query each known account for events
    for account in known_accounts {
        let account_address = account.strip_prefix("0x")
            .unwrap_or(account);
        
        let raw_events = client.get_account_events(account_address, None, None, Some(100))
            .await
            .context(format!("Failed to fetch events for account {}", account))?;
        
        for event in raw_events {
            // Parse event type to check if it's a request intent event
            let event_type = event.r#type.clone();
            
            // Handle LimitOrderEvent, OracleLimitOrderEvent, and LimitOrderFulfillmentEvent
            if event_type.contains("LimitOrderFulfillmentEvent") {
                // Try to parse as fulfillment event
                let fulfillment_data_result: Result<MvmLimitOrderFulfillmentEvent, _> = serde_json::from_value(event.data.clone());
                
                if let Ok(data) = fulfillment_data_result {
                    // Create fulfillment event
                    let fulfillment_event = FulfillmentEvent {
                        intent_id: data.intent_id.clone(),
                        intent_address: data.intent_address.clone(),
                        solver: data.solver.clone(),
                        provided_metadata: serde_json::to_string(&data.provided_metadata).unwrap_or_default(),
                        provided_amount: data.provided_amount.parse::<u64>()
                            .context("Failed to parse provided_amount")?,
                        timestamp: data.timestamp.parse::<u64>()
                            .context("Failed to parse timestamp")?,
                    };
                    
                    // Cache the fulfillment event
                    {
                        let intent_id = fulfillment_event.intent_id.clone();
                        let mut fulfillment_cache = monitor.fulfillment_cache.write().await;
                        // Check if this intent_id already exists in the cache (normalize for comparison)
                        let normalized_intent_id = crate::monitor::generic::normalize_intent_id(&intent_id);
                        if !fulfillment_cache.iter().any(|cached| crate::monitor::generic::normalize_intent_id(&cached.intent_id) == normalized_intent_id) {
                            fulfillment_cache.push(fulfillment_event.clone());
                            info!("Received fulfillment event for request intent {} by solver {}", data.intent_id, data.solver);
                        } else {
                            // Already cached, skip validation to avoid duplicate processing
                            continue;
                        }
                    }
                    
                    // Validate fulfillment event and generate approval if valid (for inflow intents)
                    // This triggers connected chain escrow release approval
                    if let Err(e) = inflow_generic::validate_and_approve_fulfillment(monitor, &fulfillment_event).await {
                        error!("Fulfillment validation failed: {}", e);
                    }
                }
            } else if event_type.contains("OracleLimitOrderEvent") {
                // Outflow intents use OracleLimitOrderEvent (from fa_intent_with_oracle)
                // All outflow request intents MUST have a reserved solver
                let data: MvmOracleLimitOrderEvent = serde_json::from_value(event.data.clone())
                    .context("Failed to parse OracleLimitOrderEvent")?;
                
                // Use reserved_solver from event (now included in the event)
                // All outflow intents must have a reserved solver
                let reserved_solver = match data.reserved_solver.clone() {
                    Some(solver) => solver,
                    None => {
                        error!("Outflow intent {} has no reserved_solver in event. Event data: {:?}", data.intent_id, event.data);
                        return Err(anyhow::anyhow!("Outflow intent must have reserved_solver, but event has None. This indicates a bug in move-intent-framework or the event was emitted before the code update."));
                    }
                };
                
                intent_events.push(RequestIntentEvent {
                    intent_id: data.intent_id.clone(),  // Use intent_id for cross-chain linking
                    requester: data.requester.clone(),
                    offered_metadata: serde_json::to_string(&data.offered_metadata).unwrap_or_default(),
                    offered_amount: data.offered_amount.parse::<u64>()
                        .context("Failed to parse offered amount")?,
                    desired_metadata: serde_json::to_string(&data.desired_metadata).unwrap_or_default(),
                    desired_amount: data.desired_amount.parse::<u64>()
                        .context("Failed to parse desired_amount")?,
                    expiry_time: data.expiry_time.parse::<u64>()
                        .context("Failed to parse expiry_time")?,
                    revocable: data.revocable,
                    reserved_solver: Some(reserved_solver),
                    connected_chain_id: None, // OracleLimitOrderEvent doesn't have connected_chain_id in the event
                    requester_address_connected_chain: None, // Not available from event, would need to query intent object
                    timestamp,
                });
            }
        }
    }
    
    Ok(intent_events)
}

