//! Inflow Fulfillment Service
//!
//! Monitors escrow deposits on connected chains and fulfills inflow intents on the hub chain.
//!
//! Flow:
//! 1. **Monitor Escrows**: Poll connected chain for escrow deposits matching tracked inflow intents
//! 2. **Fulfill Intent**: Call hub chain `fulfill_inflow_intent` when escrow is detected
//! 3. **Release Escrow**: Poll verifier for approval signature, then release escrow on connected chain

use crate::chains::{ConnectedEvmClient, ConnectedMvmClient};
use crate::config::{ConnectedChainConfig, SolverConfig};
use crate::service::tracker::{IntentTracker, TrackedIntent};
use crate::verifier_client::VerifierClient;
use anyhow::{Context, Result};
use base64::{engine::general_purpose::STANDARD, Engine};
use std::sync::Arc;
use std::time::Duration;
use tracing::{error, info, warn};

/// Inflow fulfillment service that monitors escrows and fulfills intents
pub struct InflowService {
    /// Solver configuration
    config: SolverConfig,
    /// Intent tracker for tracking signed intents (shared with other services)
    tracker: Arc<IntentTracker>,
    /// Verifier base URL (client created on-demand to avoid blocking client in async context)
    verifier_url: String,
    /// Connected chain client (MVM or EVM)
    connected_client: ConnectedChainClient,
}

/// Enum for connected chain client (MVM or EVM)
enum ConnectedChainClient {
    Mvm(ConnectedMvmClient),
    Evm(ConnectedEvmClient),
}

/// Helper struct for matching escrow events to intents
struct EscrowMatch {
    intent_id: String,
    escrow_id: String,
}

impl InflowService {
    /// Creates a new inflow fulfillment service
    ///
    /// # Arguments
    ///
    /// * `config` - Solver configuration
    /// * `tracker` - Shared intent tracker instance
    ///
    /// # Returns
    ///
    /// * `Ok(InflowService)` - Successfully created service
    /// * `Err(anyhow::Error)` - Failed to create service
    pub fn new(config: SolverConfig, tracker: Arc<IntentTracker>) -> Result<Self> {
        let verifier_url = config.service.verifier_url.clone();

        // Create connected chain client based on config
        let connected_client = match &config.connected_chain {
            ConnectedChainConfig::Mvm(chain_config) => {
                ConnectedChainClient::Mvm(ConnectedMvmClient::new(chain_config)?)
            }
            ConnectedChainConfig::Evm(chain_config) => {
                ConnectedChainClient::Evm(ConnectedEvmClient::new(chain_config)?)
            }
        };

        Ok(Self {
            config,
            tracker,
            verifier_url,
            connected_client,
        })
    }

    /// Polls the connected chain for escrow deposits matching tracked inflow intents
    ///
    /// This function queries the connected chain for escrow creation events and matches
    /// them to tracked inflow intents by intent_id. When a match is found, the intent
    /// is ready for fulfillment.
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<(TrackedIntent, String)>)` - List of (intent, escrow_id) pairs with matching escrows
    /// * `Err(anyhow::Error)` - Failed to poll escrows
    pub async fn poll_for_escrows(&self) -> Result<Vec<(TrackedIntent, String)>> {
        // Get pending inflow intents (Created state, desired_chain_id == hub_chain_id)
        let pending_intents = self
            .tracker
            .get_intents_ready_for_fulfillment(Some(true))
            .await;

        if pending_intents.is_empty() {
            // Debug: check if there are any Created intents at all
            let all_created = self.tracker.get_intents_ready_for_fulfillment(None).await;
            if !all_created.is_empty() {
                for intent in &all_created {
                    let hub_chain_id = self.config.hub_chain.chain_id;
                    let is_inflow = intent.draft_data.desired_chain_id == hub_chain_id;
                    info!(
                        "Inflow poll: Intent {} in Created state: is_inflow={}, offered_chain={}, desired_chain={}",
                        intent.intent_id, is_inflow,
                        intent.draft_data.offered_chain_id, intent.draft_data.desired_chain_id
                    );
                }
            }
            return Ok(Vec::new());
        }

        // Collect requester_addr_connected_chain from pending intents (for inflow escrow lookup)
        // Inflow intents have escrows created on the connected chain by the connected chain requester,
        // not the hub chain requester.
        let connected_chain_requester_addresses: Vec<String> = pending_intents
            .iter()
            .filter_map(|intent| intent.requester_addr_connected_chain.clone())
            .collect();

        // Query connected chain for escrow events
        let escrow_events: Vec<EscrowMatch> = match &self.connected_client {
            ConnectedChainClient::Mvm(client) => {
                if connected_chain_requester_addresses.is_empty() {
                    info!("No connected chain requester addresses found for inflow intents");
                    Vec::new()
                } else {
                    // Convert EscrowEvent to a common format for matching
                    let events = client.get_escrow_events(&connected_chain_requester_addresses, None).await?;
                    if !events.is_empty() {
                        info!("Found {} MVM escrow events", events.len());
                    }
                    events
                        .into_iter()
                        .map(|e| EscrowMatch {
                            intent_id: e.intent_id,
                            escrow_id: e.escrow_id,
                        })
                        .collect()
                }
            }
            ConnectedChainClient::Evm(client) => {
                // EVM client uses from_block/to_block instead of known_accounts
                // For now, query from block 0 (all blocks) to latest
                info!("Querying EVM chain for escrow events (from_block=0)");
                let events = match client.get_escrow_events(Some(0), None).await {
                    Ok(events) => {
                        if !events.is_empty() {
                            info!("Found {} EVM escrow events", events.len());
                        }
                        events
                    }
                    Err(e) => {
                        error!("Failed to query EVM escrow events: {}", e);
                        return Err(e);
                    }
                };
                events
                    .into_iter()
                    .map(|e| EscrowMatch {
                        intent_id: e.intent_id,
                        escrow_id: e.escrow_addr,
                    })
                    .collect()
            }
        };

        // Only log matching details if there are escrow events to match against
        if !escrow_events.is_empty() {
            info!("Matching {} pending intents against {} escrow events", pending_intents.len(), escrow_events.len());
        }

        // Match escrow events to tracked intents by intent_id
        let mut matched_intents = Vec::new();
        for intent in pending_intents {
            // Normalize intent_id for comparison
            let intent_id_normalized = normalize_intent_id(&intent.intent_id);

            for escrow in escrow_events.iter() {
                let escrow_intent_id_normalized = normalize_intent_id(&escrow.intent_id);
                if escrow_intent_id_normalized == intent_id_normalized {
                    info!("✅ Match found: intent {} matches escrow {}", intent.intent_id, escrow.escrow_id);
                    matched_intents.push((intent.clone(), escrow.escrow_id.clone()));
                    break;
                }
            }
        }

        if !matched_intents.is_empty() {
            info!("Matched {} intents with escrows", matched_intents.len());
        }

        Ok(matched_intents)
    }

    /// Fulfills an inflow intent on the hub chain
    ///
    /// Calls `fulfill_inflow_intent` on the hub chain to provide tokens
    /// to the requester. This should be called after detecting a matching escrow
    /// on the connected chain.
    ///
    /// # Arguments
    ///
    /// * `intent` - Tracked intent to fulfill
    /// * `payment_amount` - Amount of tokens to provide (should match desired_amount)
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Transaction hash
    /// * `Err(anyhow::Error)` - Failed to fulfill intent
    pub fn fulfill_inflow_intent(&self, intent: &TrackedIntent, payment_amount: u64) -> Result<String> {
        let intent_addr = intent
            .intent_addr
            .as_ref()
            .context("Intent address not set (intent not yet created on-chain)")?;

        let hub_client = crate::chains::HubChainClient::new(&self.config.hub_chain)?;
        hub_client.fulfill_inflow_intent(intent_addr, payment_amount)
    }

    /// Releases an escrow on the connected chain after getting verifier approval
    ///
    /// This function:
    /// 1. Polls the verifier for an approval signature matching the intent_id (with retries)
    /// 2. Converts the signature to the appropriate format (Ed25519 for MVM, ECDSA for EVM)
    /// 3. Calls the escrow release function on the connected chain
    ///
    /// For inflow escrows, the payment_amount is always 0 because the solver already
    /// fulfilled on the hub chain. The escrow just releases the locked tokens to the solver.
    ///
    /// # Arguments
    ///
    /// * `intent` - Tracked intent with matching escrow
    /// * `escrow_id` - Escrow object/contract address
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Transaction hash
    /// * `Err(anyhow::Error)` - Failed to release escrow
    pub async fn release_escrow(
        &self,
        intent: &TrackedIntent,
        escrow_id: &str,
    ) -> Result<String> {
        // Poll verifier for approval until escrow expiry
        let verifier_url = self.verifier_url.clone();
        let intent_id_normalized = normalize_intent_id(&intent.intent_id);
        let poll_interval = Duration::from_secs(2);
        let expiry_time = intent.expiry_time;
        
        let approval = loop {
            let current_time = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs();
            
            if current_time >= expiry_time {
                anyhow::bail!("Escrow expired while waiting for approval (expiry: {})", expiry_time);
            }
            
            let approvals = tokio::task::spawn_blocking({
                let verifier_url = verifier_url.clone();
                move || {
                    let client = VerifierClient::new(&verifier_url);
                    client.get_approvals()
                }
            })
            .await
            .context("Failed to spawn blocking task")?
            .context("Failed to get approvals")?;

            // Find approval matching this intent_id
            if let Some(approval) = approvals.iter().find(|approval| {
                let approval_intent_id_normalized = normalize_intent_id(&approval.intent_id);
                approval_intent_id_normalized == intent_id_normalized
            }) {
                info!("Found approval for intent {}", intent.intent_id);
                break approval.clone();
            }

            // Approval not found yet, wait and retry
            tokio::time::sleep(poll_interval).await;
        };

        // Decode base64 signature to bytes
        let signature_bytes = STANDARD
            .decode(&approval.signature)
            .context("Failed to decode base64 signature")?;

        // Release escrow based on chain type
        // For inflow: payment_amount = 0 (solver already fulfilled on hub chain)
        match &self.connected_client {
            ConnectedChainClient::Mvm(client) => {
                // For MVM, use complete_escrow_from_fa with Ed25519 signature
                client.complete_escrow_from_fa(escrow_id, 0, &signature_bytes)
            }
            ConnectedChainClient::Evm(client) => {
                // For EVM, use claim() with ECDSA signature via Hardhat script
                // The Hardhat script handles signing using Hardhat's signer configuration
                client.claim_escrow(escrow_id, &intent.intent_id, &signature_bytes).await
            }
        }
    }

    /// Runs the inflow fulfillment service loop
    ///
    /// This function continuously:
    /// 1. Polls for escrows matching tracked inflow intents
    /// 2. Fulfills intents on hub chain when escrows are detected
    /// 3. Releases escrows after getting verifier approval
    ///
    /// The loop runs at the configured polling interval.
    pub async fn run(&self) -> Result<()> {
        let polling_interval = Duration::from_millis(self.config.service.polling_interval_ms);
        info!("Inflow fulfillment service started (polling every {:?})", polling_interval);

        loop {
            match self.poll_for_escrows().await {
                Ok(intents_with_escrows) => {
                    for (intent, escrow_id) in intents_with_escrows {
                        info!(
                            "Found escrow {} for inflow intent: {}",
                            escrow_id, intent.intent_id
                        );

                        // Fulfill intent on hub chain
                        match self.fulfill_inflow_intent(&intent, intent.draft_data.desired_amount) {
                            Ok(tx_hash) => {
                                info!(
                                    "Fulfilled inflow intent {} on hub chain: {}",
                                    intent.intent_id, tx_hash
                                );
                                // Mark intent as fulfilled IMMEDIATELY after successful fulfillment
                                // This prevents retrying fulfillment on next poll
                                if let Err(e) = self.tracker.mark_fulfilled(&intent.draft_id).await {
                                    warn!("Failed to mark intent as fulfilled: {}", e);
                                }
                            }
                            Err(e) => {
                                error!("Failed to fulfill inflow intent {}: {}", intent.intent_id, e);
                                continue;
                            }
                        }

                        // Release escrow after a delay (wait for verifier to generate approval)
                        tokio::time::sleep(Duration::from_secs(2)).await;

                        match self
                            .release_escrow(&intent, &escrow_id)
                            .await
                        {
                            Ok(tx_hash) => {
                                info!(
                                    "Released escrow {} for intent {}: {}",
                                    escrow_id, intent.intent_id, tx_hash
                                );
                            }
                            Err(e) => {
                                error!(
                                    "Failed to release escrow {} for intent {}: {}",
                                    escrow_id, intent.intent_id, e
                                );
                            }
                        }
                    }
                }
                Err(e) => {
                    error!("Failed to poll for escrows: {}", e);
                }
            }

            tokio::time::sleep(polling_interval).await;
        }
    }
}

/// Normalize intent ID for comparison (strip 0x prefix, remove leading zeros, lowercase)
fn normalize_intent_id(intent_id: &str) -> String {
    let stripped = intent_id.strip_prefix("0x").unwrap_or(intent_id);
    // Remove leading zeros
    let trimmed = stripped.trim_start_matches('0');
    // If all zeros, keep at least one zero
    let hex_part = if trimmed.is_empty() { "0" } else { trimmed };
    format!("0x{}", hex_part.to_lowercase())
}

