//! Aptos-specific monitoring functions
//!
//! This module contains Aptos-specific event polling logic
//! for escrow events on connected Aptos chains.

use anyhow::{Result, Context};
use crate::config::Config;
use crate::aptos_client::{AptosClient, OracleLimitOrderEvent as AptosOracleLimitOrderEvent};
use crate::monitor::{EscrowEvent, ChainType};

/// Polls the connected Aptos chain for new escrow initialization events.
/// 
/// This function queries the Aptos chain's event logs for OracleLimitOrderEvent
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
pub async fn poll_aptos_escrow_events(config: &Config) -> Result<Vec<EscrowEvent>> {
    let connected_chain_apt = config.connected_chain_apt.as_ref()
        .ok_or_else(|| anyhow::anyhow!("No connected Aptos chain configured"))?;
    
    // Create Aptos client for connected chain
    let client = AptosClient::new(&connected_chain_apt.rpc_url)?;
    
    // Query events from known test accounts
    let known_accounts = connected_chain_apt.known_accounts.as_ref()
        .ok_or_else(|| anyhow::anyhow!("No known accounts configured for connected Aptos chain"))?;
    
    let mut escrow_events = Vec::new();
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
            let event_type = event.r#type.clone();
            
            // Escrows use oracle-guarded intents, so we look for OracleLimitOrderEvent
            if event_type.contains("OracleLimitOrderEvent") {
                let data: AptosOracleLimitOrderEvent = serde_json::from_value(event.data.clone())
                    .context("Failed to parse OracleLimitOrderEvent as escrow")?;
                
                // Query reserved solver address from escrow object (if reserved)
                let reserved_solver = client.get_intent_solver(&data.intent_address, &connected_chain_apt.escrow_module_address.as_ref().unwrap_or(&connected_chain_apt.intent_module_address))
                    .await
                    .ok()
                    .flatten();
                
                escrow_events.push(EscrowEvent {
                    escrow_id: data.intent_address.clone(),
                    intent_id: data.intent_id.clone(), // Use intent_id to match with hub chain request intent
                    issuer: data.requester.clone(), // For inflow escrows, this is the original requester from the hub chain (not the solver who created the escrow)
                    offered_metadata: serde_json::to_string(&data.offered_metadata).unwrap_or_default(),
                    offered_amount: data.offered_amount.parse::<u64>()
                        .context("Failed to parse offered amount")?,
                    desired_metadata: serde_json::to_string(&data.desired_metadata).unwrap_or_default(),
                    desired_amount: data.desired_amount.parse::<u64>()
                        .context("Failed to parse desired amount")?,
                    expiry_time: data.expiry_time.parse::<u64>()
                        .context("Failed to parse expiry time")?,
                    revocable: data.revocable,
                    reserved_solver,
                    chain_id: connected_chain_apt.chain_id, // Chain ID from config
                    chain_type: ChainType::Move, // This escrow came from Aptos (Move) monitoring
                    timestamp,
                });
            }
        }
    }
    
    Ok(escrow_events)
}

