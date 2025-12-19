//! Hub Chain Move VM-specific monitoring functions
//!
//! This module contains Move VM-specific event polling logic
//! for hub chain intent events. The hub chain handles
//! both inflow and outflow intents.

use anyhow::{Context, Result};
use tracing::{error, info};

use crate::monitor::generic::{EventMonitor, FulfillmentEvent, IntentEvent};
use crate::monitor::inflow_generic;
use crate::mvm_client::{
    LimitOrderEvent as MvmLimitOrderEvent,
    LimitOrderFulfillmentEvent as MvmLimitOrderFulfillmentEvent, MvmClient,
    OracleLimitOrderEvent as MvmOracleLimitOrderEvent,
};

/// Parses an amount (decimal string or hex string) and validates it doesn't exceed u64::MAX (Move contract constraint)
///
/// This function parses a string as u128 first to handle large values, then validates
/// it doesn't exceed u64::MAX since Move contracts only support u64 for amounts.
///
/// # Arguments
///
/// * `amount_str` - The amount as a string (decimal or hex, with or without 0x prefix)
/// * `field_name` - The name of the field being parsed (for error messages)
///
/// # Returns
///
/// * `Ok(u64)` - Parsed and validated amount
/// * `Err(anyhow::Error)` - Failed to parse or amount exceeds u64::MAX
#[doc(hidden)]
pub fn parse_amount_with_u64_limit(amount_str: &str, field_name: &str) -> Result<u64> {
    // Parse as u128 first to handle large values
    // Support both decimal strings and hex strings (with or without 0x prefix)
    // For EVM calldata: hex strings are exactly 64 chars (32 bytes)
    // For Move events: decimal strings are typically shorter
    let amount_u128 = if amount_str.starts_with("0x") {
        // Explicit hex string with 0x prefix
        let hex_str = &amount_str[2..];
        u128::from_str_radix(hex_str, 16)
            .with_context(|| format!("Failed to parse {} as hex number", field_name))?
    } else if amount_str.len() == 64 && amount_str.chars().all(|c| c.is_ascii_hexdigit()) {
        // Exactly 64 hex chars without 0x prefix (from EVM calldata, 32 bytes)
        u128::from_str_radix(amount_str, 16)
            .with_context(|| format!("Failed to parse {} as hex number", field_name))?
    } else {
        // Try decimal first, fall back to hex if it fails
        amount_str
            .parse::<u128>()
            .or_else(|_| {
                u128::from_str_radix(amount_str, 16)
                    .with_context(|| format!("Failed to parse {} as number (tried both decimal and hex)", field_name))
            })?
    };
    
    // Validate amount doesn't exceed u64::MAX (Move contract constraint)
    if amount_u128 > u64::MAX as u128 {
        return Err(anyhow::anyhow!(
            "{} {} exceeds Move contract limit (u64::MAX = {}). Move contracts only support u64 for amounts",
            field_name, amount_u128, u64::MAX
        ));
    }
    
    // Safe to convert since we've validated it doesn't exceed u64::MAX
    u64::try_from(amount_u128)
        .map_err(|_| anyhow::anyhow!(
            "Failed to convert {} {} to u64 (this should not happen after validation)",
            field_name, amount_u128
        ))
}

/// Polls the hub Move VM chain for new intent events.
///
/// This function queries the hub chain's event logs for new intent
/// creation events. Since module events are emitted in user transactions,
/// we query known test accounts for their events.
///
/// Handles both inflow and outflow intents:
/// - Inflow intents emit `LimitOrderEvent` (from fa_intent)
/// - Outflow intents emit `OracleLimitOrderEvent` (from fa_intent_with_oracle)
/// - Both emit `LimitOrderFulfillmentEvent` when fulfilled
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
///
/// # Returns
///
/// * `Ok(Vec<IntentEvent>)` - List of new intent events
/// * `Err(anyhow::Error)` - Failed to poll events
pub async fn poll_hub_events(monitor: &EventMonitor) -> Result<Vec<IntentEvent>> {
    // Create Move VM client for hub chain
    let client = MvmClient::new(&monitor.config.hub_chain.rpc_url)?;

    // Query active requester addresses from the intent registry
    let registry_address = &monitor.config.hub_chain.intent_module_address;
    let requester_addresses_to_poll = client
        .get_active_requesters(registry_address)
        .await
        .context("Failed to query intent registry for active requesters")?;

    // Query all registered solver addresses to poll for fulfillment events
    // Fulfillment events are emitted on the solver's account, not the requester's account
    let solver_addresses = client
        .get_all_solver_addresses(registry_address)
        .await
        .context("Failed to query solver registry for all solvers")?;

    // Combine requester and solver addresses to poll (deduplicate)
    let mut addresses_set: std::collections::HashSet<String> = requester_addresses_to_poll.iter().cloned().collect();
    for solver_addr in solver_addresses {
        addresses_set.insert(solver_addr);
    }
    let addresses_to_poll: Vec<String> = addresses_set.into_iter().collect();

    let mut intent_events = Vec::new();
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs();

    // Query each address (requesters + solvers) for events
    for address in &addresses_to_poll {
        let address_normalized = address.strip_prefix("0x").unwrap_or(address);

        let raw_events = client
            .get_account_events(address_normalized, None, None, Some(100))
            .await
            .context(format!("Failed to fetch events for address {}", address))?;

        for event in raw_events {
            // Parse event type to check if it's a intent event
            let event_type = event.r#type.clone();

            // Handle LimitOrderEvent, OracleLimitOrderEvent, and LimitOrderFulfillmentEvent
            // IMPORTANT: Check OracleLimitOrderEvent BEFORE LimitOrderEvent because
            // "OracleLimitOrderEvent".contains("LimitOrderEvent") is true!
            if event_type.contains("LimitOrderFulfillmentEvent") {
                // Try to parse as fulfillment event
                let fulfillment_data_result: Result<MvmLimitOrderFulfillmentEvent, _> =
                    serde_json::from_value(event.data.clone());

                if let Ok(data) = fulfillment_data_result {
                    // Create fulfillment event
                    // Normalize intent_id to 64 hex characters to ensure it can be safely parsed as hex
                    let normalized_intent_id = crate::monitor::generic::normalize_intent_id_to_64_chars(&data.intent_id);
                    let fulfillment_event = FulfillmentEvent {
                        intent_id: normalized_intent_id,
                        intent_address: data.intent_address.clone(),
                        solver: data.solver.clone(),
                        provided_metadata: serde_json::to_string(&data.provided_metadata)
                            .unwrap_or_default(),
                        provided_amount: parse_amount_with_u64_limit(&data.provided_amount, "Fulfillment provided_amount")?,
                        timestamp: data
                            .timestamp
                            .parse::<u64>()
                            .context("Failed to parse timestamp")?,
                    };

                    // Cache the fulfillment event
                    let is_new_fulfillment = {
                        let intent_id = fulfillment_event.intent_id.clone();
                        let mut fulfillment_cache = monitor.fulfillment_cache.write().await;
                        // Check if this intent_id already exists in the cache (normalize for comparison)
                        let normalized_intent_id =
                            crate::monitor::generic::normalize_intent_id(&intent_id);
                        if !fulfillment_cache.iter().any(|cached| {
                            crate::monitor::generic::normalize_intent_id(&cached.intent_id)
                                == normalized_intent_id
                        }) {
                            fulfillment_cache.push(fulfillment_event.clone());
                            info!(
                                "Received fulfillment event for intent {} by solver {}",
                                data.intent_id, data.solver
                            );
                            true
                        } else {
                            // Already cached, skip validation to avoid duplicate processing
                            false
                        }
                    };

                    // If this is a new fulfillment, try validation for this intent
                    if is_new_fulfillment {
                        if let Err(e) = inflow_generic::try_validate_for_intent(monitor, &fulfillment_event.intent_id).await {
                            error!("Failed to validate for intent {}: {}", fulfillment_event.intent_id, e);
                        }
                    }
                }
            } else if event_type.contains("OracleLimitOrderEvent") {
                // Outflow intents use OracleLimitOrderEvent (from fa_intent_with_oracle)
                // All outflow intents MUST have a reserved solver
                let data: MvmOracleLimitOrderEvent = serde_json::from_value(event.data.clone())
                    .context("Failed to parse OracleLimitOrderEvent")?;

                // Use reserved_solver from event (now included in the event)
                // All outflow intents must have a reserved solver
                let reserved_solver = match data.reserved_solver.clone() {
                    Some(solver) => solver,
                    None => {
                        error!(
                            "Outflow intent {} has no reserved_solver in event. Event data: {:?}",
                            data.intent_id, event.data
                        );
                        return Err(anyhow::anyhow!("Outflow intent must have reserved_solver, but event has None. This indicates a bug in move-intent-framework or the event was emitted before the code update."));
                    }
                };

                // Determine connected_chain_id for outflow intents
                // For outflow: offered_chain_id is hub chain, desired_chain_id is connected chain
                let offered_chain_id = data
                    .offered_chain_id
                    .parse::<u64>()
                    .context("Failed to parse offered_chain_id")?;
                let desired_chain_id = data
                    .desired_chain_id
                    .parse::<u64>()
                    .context("Failed to parse desired_chain_id")?;

                // If chain IDs differ, this is a cross-chain intent
                // For outflow: desired_chain_id is the connected chain
                let connected_chain_id = if offered_chain_id != desired_chain_id {
                    Some(desired_chain_id) // For outflow, desired_chain_id is the connected chain
                } else {
                    None // Regular single-chain intent (shouldn't happen for outflow, but handle gracefully)
                };

                // Convert Move event (OracleLimitOrderEvent) to verifier's internal IntentEvent structure
                // IntentEvent is NOT an on-chain event - it's the verifier's internal representation
                // used for caching and validation
                
                // Determine desired_metadata string format:
                // Use {"inner":"0x..."} to match Move's native Object<Metadata> serialization
                let desired_metadata_str = if let Some(addr) = &data.desired_metadata_address {
                    format!(r#"{{"inner":"{}"}}"#, addr)
                } else {
                    serde_json::to_string(&data.desired_metadata).unwrap_or_default()
                };
                
                intent_events.push(IntentEvent {
                    intent_id: data.intent_id.clone(), // Use intent_id for cross-chain linking
                    requester: data.requester.clone(),
                    offered_metadata: serde_json::to_string(&data.offered_metadata)
                        .unwrap_or_default(),
                    offered_amount: parse_amount_with_u64_limit(&data.offered_amount, "Request-intent offered_amount")?,
                    desired_metadata: desired_metadata_str,
                    desired_amount: parse_amount_with_u64_limit(&data.desired_amount, "Request-intent desired_amount")?,
                    expiry_time: data
                        .expiry_time
                        .parse::<u64>()
                        .context("Failed to parse expiry_time")?,
                    revocable: data.revocable,
                    reserved_solver: Some(reserved_solver),
                    connected_chain_id,
                    requester_address_connected_chain: data
                        .requester_address_connected_chain
                        .clone(),
                    timestamp,
                });
            } else if event_type.contains("LimitOrderEvent") && !event_type.contains("Fulfillment")
            {
                // Inflow intents use LimitOrderEvent (from fa_intent)
                // This is for regular intents and inflow cross-chain intents
                let data: MvmLimitOrderEvent = serde_json::from_value(event.data.clone())
                    .context("Failed to parse LimitOrderEvent")?;

                // Check if this is a cross-chain intent (has different offered_chain_id and desired_chain_id)
                let offered_chain_id = data
                    .offered_chain_id
                    .parse::<u64>()
                    .context("Failed to parse offered_chain_id")?;
                let desired_chain_id = data
                    .desired_chain_id
                    .parse::<u64>()
                    .context("Failed to parse desired_chain_id")?;

                // If chain IDs differ, this is a cross-chain intent
                // For inflow: offered_chain_id is connected chain, desired_chain_id is hub chain
                // For outflow: offered_chain_id is hub chain, desired_chain_id is connected chain
                let connected_chain_id = if offered_chain_id != desired_chain_id {
                    Some(offered_chain_id) // For inflow, offered_chain_id is the connected chain
                } else {
                    None // Regular single-chain intent
                };

                let reserved_solver = data.reserved_solver.clone();
                
                // Determine offered_metadata string format:
                // Use {"inner":"0x..."} to match Move's native Object<Metadata> serialization
                let offered_metadata_str = if let Some(addr) = &data.offered_metadata_address {
                    format!(r#"{{"inner":"{}"}}"#, addr)
                } else {
                    serde_json::to_string(&data.offered_metadata).unwrap_or_default()
                };
                
                intent_events.push(IntentEvent {
                    intent_id: data.intent_id.clone(), // Use intent_id for cross-chain linking
                    requester: data.requester.clone(),
                    offered_metadata: offered_metadata_str,
                    offered_amount: parse_amount_with_u64_limit(&data.offered_amount, "Request-intent offered_amount")?,
                    desired_metadata: serde_json::to_string(&data.desired_metadata)
                        .unwrap_or_default(),
                    desired_amount: parse_amount_with_u64_limit(&data.desired_amount, "Request-intent desired_amount")?,
                    expiry_time: data
                        .expiry_time
                        .parse::<u64>()
                        .context("Failed to parse expiry_time")?,
                    revocable: data.revocable,
                    reserved_solver,
                    connected_chain_id,
                    requester_address_connected_chain: data.requester_address_connected_chain.clone(),
                    timestamp,
                });
            } else if event_type.contains("OracleLimitOrderEvent") {
                // Outflow intents use OracleLimitOrderEvent (from fa_intent_with_oracle)
                // All outflow intents MUST have a reserved solver
                let data: MvmOracleLimitOrderEvent = serde_json::from_value(event.data.clone())
                    .context("Failed to parse OracleLimitOrderEvent")?;

                // Use reserved_solver from event (now included in the event)
                // All outflow intents must have a reserved solver
                let reserved_solver = match data.reserved_solver.clone() {
                    Some(solver) => solver,
                    None => {
                        error!(
                            "Outflow intent {} has no reserved_solver in event. Event data: {:?}",
                            data.intent_id, event.data
                        );
                        return Err(anyhow::anyhow!("Outflow intent must have reserved_solver, but event has None. This indicates a bug in move-intent-framework or the event was emitted before the code update."));
                    }
                };

                // Determine connected_chain_id for outflow intents
                // For outflow: offered_chain_id is hub chain, desired_chain_id is connected chain
                let offered_chain_id = data
                    .offered_chain_id
                    .parse::<u64>()
                    .context("Failed to parse offered_chain_id")?;
                let desired_chain_id = data
                    .desired_chain_id
                    .parse::<u64>()
                    .context("Failed to parse desired_chain_id")?;

                // If chain IDs differ, this is a cross-chain intent
                // For outflow: desired_chain_id is the connected chain
                let connected_chain_id = if offered_chain_id != desired_chain_id {
                    Some(desired_chain_id) // For outflow, desired_chain_id is the connected chain
                } else {
                    None // Regular single-chain intent (shouldn't happen for outflow, but handle gracefully)
                };

                // Convert Move event (OracleLimitOrderEvent) to verifier's internal IntentEvent structure
                // IntentEvent is NOT an on-chain event - it's the verifier's internal representation
                // used for caching and validation
                
                // Determine desired_metadata string format:
                // Use {"inner":"0x..."} to match Move's native Object<Metadata> serialization
                let desired_metadata_str = if let Some(addr) = &data.desired_metadata_address {
                    format!(r#"{{"inner":"{}"}}"#, addr)
                } else {
                    serde_json::to_string(&data.desired_metadata).unwrap_or_default()
                };
                
                intent_events.push(IntentEvent {
                    intent_id: data.intent_id.clone(), // Use intent_id for cross-chain linking
                    requester: data.requester.clone(),
                    offered_metadata: serde_json::to_string(&data.offered_metadata)
                        .unwrap_or_default(),
                    offered_amount: parse_amount_with_u64_limit(&data.offered_amount, "Request-intent offered_amount")?,
                    desired_metadata: desired_metadata_str,
                    desired_amount: parse_amount_with_u64_limit(&data.desired_amount, "Request-intent desired_amount")?,
                    expiry_time: data
                        .expiry_time
                        .parse::<u64>()
                        .context("Failed to parse expiry_time")?,
                    revocable: data.revocable,
                    reserved_solver: Some(reserved_solver),
                    connected_chain_id,
                    requester_address_connected_chain: data
                        .requester_address_connected_chain
                        .clone(),
                    timestamp,
                });
            }
        }
    }

    Ok(intent_events)
}
