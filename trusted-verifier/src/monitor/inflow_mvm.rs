//! Inflow Move VM-specific monitoring functions
//!
//! This module contains Move VM-specific event polling logic
//! for escrow events on connected Move VM chains.

use crate::config::Config;
use crate::monitor::generic::{ChainType, EscrowEvent};
use crate::monitor::hub_mvm::parse_amount_with_u64_limit;
use crate::mvm_client::{MvmClient, OracleLimitOrderEvent as MvmOracleLimitOrderEvent};
use anyhow::{Context, Result};

/// Polls the connected Move VM chain for new escrow initialization events.
///
/// This function queries the Move VM chain's event logs for OracleLimitOrderEvent
/// events emitted by escrow intents. It converts them to EscrowEvent format
/// for consistent processing.
///
/// # Arguments
///
/// * `config` - Service configuration
///
/// # Returns
///
/// * `Ok(Vec<EscrowEvent>)` - List of new escrow events
/// * `Err(anyhow::Error)` - Failed to poll events
pub async fn poll_mvm_escrow_events(config: &Config) -> Result<Vec<EscrowEvent>> {
    let connected_chain_mvm = config
        .connected_chain_mvm
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("No connected Move VM chain configured"))?;

    // Create Move VM client for connected chain
    let client = MvmClient::new(&connected_chain_mvm.rpc_url)?;

    // Query events from known test accounts
    let known_accounts = connected_chain_mvm.known_accounts.as_ref().ok_or_else(|| {
        anyhow::anyhow!("No known accounts configured for connected Move VM chain")
    })?;

    let mut escrow_events = Vec::new();
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs();

    // Query each known account for events
    for account in known_accounts {
        let account_address = account.strip_prefix("0x").unwrap_or(account);

        let raw_events = client
            .get_account_events(account_address, None, None, Some(100))
            .await
            .context(format!("Failed to fetch events for account {}", account))?;

        for event in raw_events {
            let event_type = event.r#type.clone();

            // Escrows use oracle-guarded intents, so we look for OracleLimitOrderEvent
            if event_type.contains("OracleLimitOrderEvent") {
                let data: MvmOracleLimitOrderEvent = serde_json::from_value(event.data.clone())
                    .with_context(|| format!(
                        "Failed to parse OracleLimitOrderEvent as escrow. Event type: {}, Event data: {}",
                        event_type,
                        serde_json::to_string_pretty(&event.data).unwrap_or_else(|_| format!("{:?}", event.data))
                    ))?;

                // Use reserved_solver from event (now included in the event)
                let reserved_solver = data.reserved_solver.clone();

                escrow_events.push(EscrowEvent {
                    escrow_id: data.intent_address.clone(),
                    intent_id: data.intent_id.clone(), // Use intent_id to match with hub chain request intent
                    issuer: data.requester.clone(), // For inflow escrows, this is the original requester from the hub chain (not the solver who created the escrow)
                    offered_metadata: serde_json::to_string(&data.offered_metadata)
                        .unwrap_or_default(),
                    offered_amount: parse_amount_with_u64_limit(&data.offered_amount, "Escrow offered_amount")?,
                    desired_metadata: serde_json::to_string(&data.desired_metadata)
                        .unwrap_or_default(),
                    desired_amount: parse_amount_with_u64_limit(&data.desired_amount, "Escrow desired_amount")?,
                    expiry_time: data
                        .expiry_time
                        .parse::<u64>()
                        .context("Failed to parse expiry time")?,
                    revocable: data.revocable,
                    reserved_solver,
                    chain_id: connected_chain_mvm.chain_id, // Chain ID from config
                    chain_type: ChainType::Mvm, // This escrow came from Move VM monitoring
                    timestamp,
                });
            }
        }
    }

    Ok(escrow_events)
}
