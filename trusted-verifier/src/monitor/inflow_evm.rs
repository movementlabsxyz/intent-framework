//! Inflow EVM-specific monitoring functions
//!
//! This module contains EVM-specific event polling logic
//! for escrow events on connected EVM chains.

use crate::config::Config;
use crate::evm_client::EvmClient;
use crate::monitor::generic::{ChainType, EscrowEvent};
use anyhow::{Context, Result};

/// Polls the EVM connected chain for new escrow initialization events.
///
/// This function queries the EVM chain's event logs for EscrowInitialized events
/// emitted by the IntentEscrow contract. It converts them to EscrowEvent format
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
pub async fn poll_evm_escrow_events(config: &Config) -> Result<Vec<EscrowEvent>> {
    let connected_chain_evm = config
        .connected_chain_evm
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("No connected EVM chain configured"))?;

    // Create EVM client for connected chain
    let client = EvmClient::new(
        &connected_chain_evm.rpc_url,
        &connected_chain_evm.escrow_contract_address,
    )
    .context(format!(
        "Failed to create EVM client for RPC URL: {}",
        connected_chain_evm.rpc_url
    ))?;

    // Get current block number to track progress
    let current_block = client.get_block_number().await.context(format!(
        "Failed to get block number from EVM chain at {}",
        connected_chain_evm.rpc_url
    ))?;

    // Get current block number to use as "to_block"
    // For "from_block", we could track the last processed block, but for now use a recent block
    let from_block = if current_block > 1000 {
        Some(current_block - 1000) // Look back 1000 blocks
    } else {
        Some(0)
    };

    // Query EVM chain for EscrowInitialized events
    let evm_events = client.get_escrow_initialized_events(from_block, None).await
        .with_context(|| format!("Failed to fetch EVM escrow events from chain {} (RPC: {}, contract: {}, from_block: {:?})", 
            connected_chain_evm.chain_id, connected_chain_evm.rpc_url, connected_chain_evm.escrow_contract_address, from_block))?;

    let mut escrow_events = Vec::new();
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs();

    for event in evm_events {
        // Convert EVM event to EscrowEvent format
        // Note: EVM escrows don't have all the same fields as Move VM escrows
        // We'll use placeholder values for fields that don't exist in EVM

        // Convert intent_id from hex string to address format
        // EVM intent_id is uint256, we'll use it as-is (it's already hex)
        let intent_id = event.intent_id.clone();

        // For EVM, escrow_id is the intent_id (escrow is keyed by intent_id)
        let escrow_id = intent_id.clone();

        escrow_events.push(EscrowEvent {
            escrow_id,
            intent_id,
            issuer: event.maker.clone(), // maker is the escrow creator
            offered_metadata: format!("{{\"token\":\"{}\"}}", event.token), // Store token address in metadata
            offered_amount: 0, // We don't have amount from EscrowInitialized event, would need to query contract
            desired_metadata: "{}".to_string(), // Not available in EscrowInitialized event
            desired_amount: 0, // Not available in EscrowInitialized event
            expiry_time: 0, // Not available in EscrowInitialized event (would need to query contract)
            revocable: false, // EVM escrows are always non-revocable
            reserved_solver: Some(event.reserved_solver.clone()),
            chain_id: connected_chain_evm.chain_id,
            chain_type: ChainType::Evm, // This escrow came from EVM monitoring
            timestamp,
        });
    }

    Ok(escrow_events)
}
