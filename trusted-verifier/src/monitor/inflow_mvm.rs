//! Inflow Move VM-specific monitoring functions
//!
//! This module contains Move VM-specific event polling logic
//! for escrow events on connected Move VM chains.

use crate::monitor::generic::{ChainType, EscrowEvent, EventMonitor};
use crate::monitor::hub_mvm::parse_amount_with_u64_limit;
use crate::mvm_client::{MvmClient, OracleLimitOrderEvent as MvmOracleLimitOrderEvent};
use anyhow::{Context, Result};
use std::collections::HashSet;

/// Polls the connected Move VM chain for new escrow initialization events.
///
/// For inflow intents, escrows are created by requesters on the connected chain.
/// The requester addresses come from the hub chain intents' `requester_addr_connected_chain`
/// field (stored on hub).
///
/// # Arguments
///
/// * `monitor` - Event monitor instance (to access cached hub intents)
///
/// # Returns
///
/// * `Ok(Vec<EscrowEvent>)` - List of new escrow events
/// * `Err(anyhow::Error)` - Failed to poll events
pub async fn poll_mvm_escrow_events(monitor: &EventMonitor) -> Result<Vec<EscrowEvent>> {
    let connected_chain_mvm = monitor
        .config
        .connected_chain_mvm
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("No connected Move VM chain configured"))?;

    // Create Move VM client for connected chain
    let client = MvmClient::new(&connected_chain_mvm.rpc_url)?;

    // Get requester_addr_connected_chain from cached hub chain intents
    // These are the addresses that created escrows on the connected chain
    let connected_chain_id = connected_chain_mvm.chain_id;
    let requester_addresses_to_poll: Vec<String> = {
        let event_cache = monitor.event_cache.read().await;
        let mut addresses = HashSet::new();

        for intent in event_cache.iter() {
            // For inflow intents, escrows are created on connected_chain_id
            // The intent's connected_chain_id tells us which chain the escrow is on
            if intent.connected_chain_id == Some(connected_chain_id) {
                if let Some(ref addr) = intent.requester_addr_connected_chain {
                    addresses.insert(addr.clone());
                }
            }
        }

        addresses.into_iter().collect()
    };

    let mut escrow_events = Vec::new();
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs();

    // Query each requester's connected chain address for escrow events
    for address in &requester_addresses_to_poll {
        let address_normalized = address.strip_prefix("0x").unwrap_or(address);

        let raw_events = client
            .get_account_events(address_normalized, None, None, Some(100))
            .await
            .context(format!(
                "Failed to fetch events for address {}",
                address
            ))?;

        for event in raw_events {
            let event_type = event.r#type.clone();

            // Escrows use oracle-guarded intents, so we look for OracleLimitOrderEvent
            if event_type.contains("OracleLimitOrderEvent") {
                let data: MvmOracleLimitOrderEvent = serde_json::from_value(event.data.clone())
                    .with_context(|| {
                        format!(
                            "Failed to parse OracleLimitOrderEvent as escrow. Event type: {}, Event data: {}",
                            event_type,
                            serde_json::to_string_pretty(&event.data)
                                .unwrap_or_else(|_| format!("{:?}", event.data))
                        )
                    })?;

                // Use reserved_solver from event (now included in the event)
                let reserved_solver = data.reserved_solver.clone();

                escrow_events.push(EscrowEvent {
                    escrow_id: data.intent_addr.clone(),
                    intent_id: data.intent_id.clone(), // Use intent_id to match with hub chain intent
                    offered_metadata: serde_json::to_string(&data.offered_metadata)
                        .unwrap_or_default(),
                    offered_amount: parse_amount_with_u64_limit(
                        &data.offered_amount,
                        "Escrow offered_amount",
                    )?,
                    desired_metadata: serde_json::to_string(&data.desired_metadata)
                        .unwrap_or_default(),
                    desired_amount: parse_amount_with_u64_limit(
                        &data.desired_amount,
                        "Escrow desired_amount",
                    )?,
                    revocable: data.revocable,
                    requester_addr: data.requester_addr.clone(), // For inflow escrows, this is the requester
                    reserved_solver_addr: reserved_solver,
                    chain_id: connected_chain_mvm.chain_id, // Chain ID from config
                    chain_type: ChainType::Mvm, // This escrow came from Move VM monitoring
                    expiry_time: data
                        .expiry_time
                        .parse::<u64>()
                        .context("Failed to parse expiry time")?,
                    timestamp,
                });
            }
        }
    }

    Ok(escrow_events)
}
