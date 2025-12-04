//! Outflow Fulfillment Service
//!
//! Executes transfers on connected chains and fulfills outflow intents on the hub chain.
//!
//! Flow:
//! 1. **Execute Transfer**: Transfer tokens on connected chain to requester_address_connected_chain
//! 2. **Get Verifier Approval**: Call verifier `/validate-outflow-fulfillment` with transaction hash
//! 3. **Fulfill Intent**: Call hub chain `fulfill_outflow_intent` with verifier signature

use crate::chains::{ConnectedEvmClient, ConnectedMvmClient, HubChainClient};
use crate::config::{ConnectedChainConfig, SolverConfig};
use crate::service::tracker::{IntentTracker, TrackedIntent};
use crate::verifier_client::{ValidateOutflowFulfillmentRequest, VerifierClient};
use anyhow::{Context, Result};
use base64::{engine::general_purpose::STANDARD, Engine};
use std::sync::Arc;
use std::time::Duration;
use tracing::{error, info, warn};

/// Outflow fulfillment service that executes transfers and fulfills intents
pub struct OutflowService {
    /// Solver configuration
    config: SolverConfig,
    /// Intent tracker for tracking signed intents (shared with other services)
    tracker: Arc<IntentTracker>,
    /// Connected chain client (MVM or EVM)
    connected_client: ConnectedChainClient,
}

/// Enum for connected chain client (MVM or EVM)
enum ConnectedChainClient {
    Mvm(ConnectedMvmClient),
    Evm(ConnectedEvmClient),
}

impl OutflowService {
    /// Creates a new outflow fulfillment service
    ///
    /// # Arguments
    ///
    /// * `config` - Solver configuration
    /// * `tracker` - Shared intent tracker instance
    /// * `hub_client` - Hub chain client instance
    ///
    /// # Returns
    ///
    /// * `Ok(OutflowService)` - Successfully created service
    /// * `Err(anyhow::Error)` - Failed to create service
    pub fn new(
        config: SolverConfig,
        tracker: Arc<IntentTracker>,
    ) -> Result<Self> {
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
            connected_client,
        })
    }

    /// Polls for pending outflow intents and executes transfers on connected chain
    ///
    /// This function queries the tracker for pending outflow intents (Created state, is_inflow = false)
    /// and executes token transfers on the connected chain to the requester's address.
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<(TrackedIntent, String)>)` - List of (intent, transaction_hash) pairs for transfers executed
    /// * `Err(anyhow::Error)` - Failed to execute transfers
    pub async fn poll_and_execute_transfers(&self) -> Result<Vec<(TrackedIntent, String)>> {
        // Get pending outflow intents (Created state, is_inflow = false)
        let pending_intents = self
            .tracker
            .get_intents_ready_for_fulfillment(Some(false))
            .await;

        if pending_intents.is_empty() {
            return Ok(Vec::new());
        }

        let mut executed_transfers = Vec::new();

        for intent in pending_intents {
            // Get requester_address_connected_chain from intent
            // TODO: Query intent object on hub chain to get requester_address_connected_chain
            // For now, we'll need to store this in TrackedIntent or query it
            // This is a placeholder - we need to implement intent object querying
            let requester_address_connected_chain = match self.get_requester_address_connected_chain(&intent).await {
                Ok(addr) => addr,
                Err(e) => {
                    warn!("Failed to get requester_address_connected_chain for intent {}: {}", intent.intent_id, e);
                    continue;
                }
            };

            // Execute transfer on connected chain
            let tx_hash = match self.execute_connected_transfer(&intent, &requester_address_connected_chain).await {
                Ok(hash) => hash,
                Err(e) => {
                    error!("Failed to execute transfer for intent {}: {}", intent.intent_id, e);
                    continue;
                }
            };

            info!("Executed outflow transfer for intent {}: tx_hash={}", intent.intent_id, tx_hash);
            executed_transfers.push((intent, tx_hash));
        }

        Ok(executed_transfers)
    }

    /// Executes a token transfer on the connected chain with intent_id embedded
    ///
    /// # Arguments
    ///
    /// * `intent` - Tracked intent to execute transfer for
    /// * `recipient` - Recipient address on connected chain (requester_address_connected_chain)
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Transaction hash
    /// * `Err(anyhow::Error)` - Failed to execute transfer
    async fn execute_connected_transfer(
        &self,
        intent: &TrackedIntent,
        recipient: &str,
    ) -> Result<String> {
        let desired_token = &intent.draft_data.desired_token;
        let desired_amount = intent.draft_data.desired_amount;

        match &self.connected_client {
            ConnectedChainClient::Mvm(client) => {
                // MVM: Use transfer_with_intent_id function
                client.transfer_with_intent_id(recipient, desired_token, desired_amount, &intent.intent_id)
            }
            ConnectedChainClient::Evm(client) => {
                // EVM: Use transfer_with_intent_id via Hardhat script
                // Same approach as inflow's claim_escrow
                client.transfer_with_intent_id(desired_token, recipient, desired_amount, &intent.intent_id).await
            }
        }
    }

    /// Gets the requester's address on the connected chain from the intent object
    ///
    /// # Arguments
    ///
    /// * `intent` - Tracked intent
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Requester address on connected chain
    /// * `Err(anyhow::Error)` - Failed to query intent object
    async fn get_requester_address_connected_chain(&self, _intent: &TrackedIntent) -> Result<String> {
        // TODO: Query intent object on hub chain to get requester_address_connected_chain field
        // For now, return an error to indicate this needs to be implemented
        anyhow::bail!(
            "get_requester_address_connected_chain not yet implemented. Need to query intent object on hub chain."
        )
    }

    /// Gets verifier approval for an outflow fulfillment transaction
    ///
    /// # Arguments
    ///
    /// * `transaction_hash` - Transaction hash on connected chain
    /// * `chain_type` - Chain type: "mvm" or "evm"
    /// * `intent_id` - Intent ID
    ///
    /// # Returns
    ///
    /// * `Ok(ApprovalSignature)` - Verifier approval signature
    /// * `Err(anyhow::Error)` - Failed to get approval
    pub async fn get_verifier_approval(
        &self,
        transaction_hash: &str,
        chain_type: &str,
        intent_id: &str,
    ) -> Result<Vec<u8>> {
        let request = ValidateOutflowFulfillmentRequest {
            transaction_hash: transaction_hash.to_string(),
            chain_type: chain_type.to_string(),
            intent_id: Some(intent_id.to_string()),
        };

        // Call verifier API (blocking call)
        let response = tokio::task::spawn_blocking({
            let base_url = self.config.service.verifier_url.clone();
            let request = request.clone();
            move || {
                let client = VerifierClient::new(&base_url);
                client.validate_outflow_fulfillment(&request)
            }
        })
        .await
        .context("Failed to spawn blocking task for verifier approval")??;

        if !response.validation.valid {
            anyhow::bail!(
                "Verifier validation failed: {}",
                response.validation.message
            );
        }

        let signature = response
            .approval_signature
            .context("Missing approval signature in valid response")?;

        // Decode base64 signature to bytes
        let signature_bytes = STANDARD
            .decode(&signature.signature)
            .context("Failed to decode base64 signature")?;

        Ok(signature_bytes)
    }

    /// Fulfills an outflow intent on the hub chain with verifier approval
    ///
    /// # Arguments
    ///
    /// * `intent` - Tracked intent to fulfill
    /// * `verifier_signature_bytes` - Verifier's Ed25519 signature as bytes
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - Transaction hash
    /// * `Err(anyhow::Error)` - Failed to fulfill intent
    pub async fn fulfill_outflow_intent(
        &self,
        intent: &TrackedIntent,
        verifier_signature_bytes: &[u8],
    ) -> Result<String> {
        let intent_address = intent
            .intent_address
            .as_ref()
            .context("Intent address not set (intent not created on-chain)")?;

        // Execute fulfillment (blocking call)
        tokio::task::spawn_blocking({
            let intent_address = intent_address.clone();
            let signature = verifier_signature_bytes.to_vec();
            let hub_config = self.config.hub_chain.clone();
            move || {
                let hub_client = HubChainClient::new(&hub_config)?;
                hub_client.fulfill_outflow_intent(&intent_address, &signature)
            }
        })
        .await
        .context("Failed to spawn blocking task for hub fulfillment")?
    }

    /// Main service loop that continuously processes outflow intents
    ///
    /// This loop:
    /// 1. Polls for pending outflow intents and executes transfers
    /// 2. Gets verifier approval for executed transfers
    /// 3. Fulfills hub intents with verifier signatures
    ///
    /// # Arguments
    ///
    /// * `polling_interval` - Interval between polling cycles
    pub async fn run(&self, polling_interval: Duration) {
        info!("Outflow fulfillment service started");

        loop {
            match self.poll_and_execute_transfers().await {
                Ok(executed_transfers) => {
                    for (intent, tx_hash) in executed_transfers {
                        // Get verifier approval
                        let chain_type = match &self.connected_client {
                            ConnectedChainClient::Mvm(_) => "mvm",
                            ConnectedChainClient::Evm(_) => "evm",
                        };

                        match self.get_verifier_approval(&tx_hash, chain_type, &intent.intent_id).await {
                            Ok(signature_bytes) => {
                                // Fulfill hub intent
                                match self.fulfill_outflow_intent(&intent, &signature_bytes).await {
                                    Ok(fulfill_tx_hash) => {
                                        info!(
                                            "Successfully fulfilled outflow intent {}: fulfill_tx={}",
                                            intent.intent_id, fulfill_tx_hash
                                        );
                                        // Mark intent as fulfilled
                                        if let Err(e) = self.tracker.mark_fulfilled(&intent.draft_id).await {
                                            error!("Failed to mark intent {} as fulfilled: {}", intent.draft_id, e);
                                        }
                                    }
                                    Err(e) => {
                                        error!("Failed to fulfill outflow intent {}: {}", intent.intent_id, e);
                                    }
                                }
                            }
                            Err(e) => {
                                error!("Failed to get verifier approval for intent {}: {}", intent.intent_id, e);
                            }
                        }
                    }
                }
                Err(e) => {
                    error!("Failed to poll and execute transfers: {}", e);
                }
            }

            tokio::time::sleep(polling_interval).await;
        }
    }
}

