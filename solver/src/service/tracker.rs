//! Intent Tracker Service
//!
//! Tracks the lifecycle of intents from draftintent to on-chain creation to fulfillment.
//!
//! Flow:
//! 1. **Draft-intent (Signed state)**: Solver signs a draftintent and submits signature to verifier.
//!    The tracker stores this draftintent, waiting for the requester to create it on-chain.
//! 2. **Request-intent (Created state)**: Requester creates the intent on-chain using the solver's signature.
//!    The tracker detects this via `poll_for_created_intents()` and updates state to Created.
//! 3. **Fulfilled Intent (Fulfilled state)**: Intent has been fulfilled by the solver.
//!
//! The tracker distinguishes between inflow and outflow intents for fulfillment routing.

use anyhow::{Context, Result};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::acceptance::DraftintentData;
use crate::chains::HubChainClient;
use crate::config::{ChainConfig, SolverConfig};

/// State of a tracked intent
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IntentState {
    /// Draft-intent has been signed and submitted to verifier, waiting for on-chain intent creation
    Signed,
    /// Request-intent has been created on-chain, ready for fulfillment
    Created,
    /// Request-intent has been fulfilled
    Fulfilled,
}

/// A tracked intent with its state and metadata
#[derive(Debug, Clone)]
pub struct TrackedIntent {
    /// Draft ID from verifier
    pub draft_id: String,
    /// Intent ID (for cross-chain linking)
    pub intent_id: String,
    /// Current state
    pub state: IntentState,
    /// Draft data (for matching with on-chain events)
    pub draft_data: DraftintentData,
    /// Requester address
    pub requester_address: String,
    /// Expiry timestamp
    pub expiry_time: u64,
    /// Intent object address (set when created on-chain)
    pub intent_address: Option<String>,
    /// Whether this is an inflow intent (tokens locked on connected chain)
    pub is_inflow: bool,
}

/// Intent tracker that monitors signed intents and their on-chain creation
pub struct IntentTracker {
    /// In-memory storage of tracked intents (keyed by draft_id)
    intents: Arc<RwLock<HashMap<String, TrackedIntent>>>,
    /// Set of requester addresses to query for events (tracked from signed intents)
    requester_addresses: Arc<RwLock<std::collections::HashSet<String>>>,
    /// Hub chain client for querying intent events
    hub_client: HubChainClient,
    /// Hub chain configuration
    hub_config: ChainConfig,
}

impl IntentTracker {
    /// Creates a new intent tracker
    ///
    /// # Arguments
    ///
    /// * `config` - Solver configuration
    ///
    /// # Returns
    ///
    /// * `Ok(IntentTracker)` - Successfully created tracker
    /// * `Err(anyhow::Error)` - Failed to create tracker
    pub fn new(config: &SolverConfig) -> Result<Self> {
        let hub_client = HubChainClient::new(&config.hub_chain)?;

        Ok(Self {
            intents: Arc::new(RwLock::new(HashMap::new())),
            requester_addresses: Arc::new(RwLock::new(std::collections::HashSet::new())),
            hub_client,
            hub_config: config.hub_chain.clone(),
        })
    }

    /// Adds a signed draftintent to tracking
    ///
    /// Called after successfully submitting a signature to the verifier.
    /// This tracks a **draftintent** (not yet on-chain) that the solver has signed.
    /// The tracker will monitor for when the requester creates the corresponding
    /// **intent** on-chain.
    ///
    /// # Arguments
    ///
    /// * `draft_id` - Draft ID from verifier
    /// * `draft_data` - Parsed draft data
    /// * `requester_address` - Requester address
    /// * `expiry_time` - Expiry timestamp
    ///
    /// # Returns
    ///
    /// * `Ok(())` - Successfully added
    /// * `Err(anyhow::Error)` - Failed to add
    pub async fn add_signed_intent(
        &self,
        draft_id: String,
        draft_data: DraftintentData,
        requester_address: String,
        expiry_time: u64,
    ) -> Result<()> {
        // Determine if this is an inflow or outflow intent
        // Inflow: tokens locked on connected chain (offered_chain_id != hub_chain_id)
        // Outflow: tokens locked on hub chain (offered_chain_id == hub_chain_id)
        let hub_chain_id = self.hub_config.chain_id;
        let is_inflow = draft_data.offered_chain_id != hub_chain_id;

        // Generate intent_id from draft_id (for now, use draft_id as intent_id)
        // In production, this would be derived from the draft data
        let intent_id = draft_id.clone();

        let tracked = TrackedIntent {
            draft_id: draft_id.clone(),
            intent_id,
            state: IntentState::Signed,
            draft_data,
            requester_address: requester_address.clone(),
            expiry_time,
            intent_address: None,
            is_inflow,
        };

        // Track requester address for event querying
        {
            let mut addresses = self.requester_addresses.write().await;
            addresses.insert(requester_address);
        }

        let mut intents = self.intents.write().await;
        intents.insert(draft_id, tracked);

        Ok(())
    }

    /// Polls the hub chain for intent creation events and updates tracked intents
    ///
    /// Queries the hub chain for **intent creation events** (LimitOrderEvent, OracleLimitOrderEvent).
    /// Matches these on-chain events to tracked **draftintents** by comparing intent data.
    /// When a match is found, updates the tracked intent from `Signed` (draftintent) to `Created` (on-chain intent).
    ///
    /// # Returns
    ///
    /// * `Ok(usize)` - Number of intents that transitioned to Created state
    /// * `Err(anyhow::Error)` - Failed to poll
    pub async fn poll_for_created_intents(&self) -> Result<usize> {
        // Get requester addresses from tracked intents
        let requester_addresses: Vec<String> = {
            let addresses = self.requester_addresses.read().await;
            addresses.iter().cloned().collect()
        };

        // If no requester addresses, we can't query - return 0
        if requester_addresses.is_empty() {
            return Ok(0);
        }

        // Query hub chain for intent creation events
        let events = self
            .hub_client
            .get_intent_events(&requester_addresses, None)
            .await
            .context("Failed to query hub chain for intent events")?;

        let mut updated_count = 0;
        let mut intents = self.intents.write().await;

        for event in events {
            // Try to match event to a tracked intent
            // Match by comparing draft data (amounts, tokens, chain IDs)
            for (_draft_id, tracked) in intents.iter_mut() {
                if tracked.state != IntentState::Signed {
                    continue; // Already processed
                }

                // Normalize intent_id for comparison (strip 0x prefix, pad to 64 chars)
                let event_intent_id = normalize_intent_id(&event.intent_id);
                let tracked_intent_id = normalize_intent_id(&tracked.intent_id);

                // Match by intent_id (if available) or by draft data
                let matches = if event_intent_id == tracked_intent_id {
                    true
                } else {
                    // Fallback: match by comparing amounts and chain IDs
                    event.offered_amount == tracked.draft_data.offered_amount.to_string()
                        && event.desired_amount == tracked.draft_data.desired_amount.to_string()
                        && event.offered_chain_id == tracked.draft_data.offered_chain_id.to_string()
                        && event.desired_chain_id == tracked.draft_data.desired_chain_id.to_string()
                        && event.requester == tracked.requester_address
                };

                if matches {
                    tracked.state = IntentState::Created;
                    tracked.intent_address = Some(event.intent_address.clone());
                    updated_count += 1;
                    break; // Found match, move to next event
                }
            }
        }

        Ok(updated_count)
    }

    /// Gets intents ready for fulfillment
    ///
    /// Returns **intents** (NOT draftintents) in `Created` state that are ready for fulfillment.
    ///
    /// These are on-chain intents that:
    /// 1. Were originally draftintents signed by the solver (Signed state)
    /// 2. Have been created on-chain by the requester (Created state)
    /// 3. Are now ready for the solver to fulfill
    ///
    /// Optionally filtered by inflow/outflow type.
    ///
    /// # Arguments
    ///
    /// * `inflow_only` - If Some(true), return only inflow intents. If Some(false), return only outflow intents. If None, return all.
    ///
    /// # Returns
    ///
    /// * `Vec<TrackedIntent>` - List of intents (Created state) ready for fulfillment
    pub async fn get_intents_ready_for_fulfillment(&self, inflow_only: Option<bool>) -> Vec<TrackedIntent> {
        let intents = self.intents.read().await;

        intents
            .values()
            .filter(|intent| {
                // Only return Created intents
                if intent.state != IntentState::Created {
                    return false;
                }

                // Filter by inflow/outflow if specified
                if let Some(inflow) = inflow_only {
                    if intent.is_inflow != inflow {
                        return false;
                    }
                }

                true
            })
            .cloned()
            .collect()
    }

    /// Marks an intent as fulfilled
    ///
    /// # Arguments
    ///
    /// * `draft_id` - Draft ID of the intent to mark as fulfilled
    ///
    /// # Returns
    ///
    /// * `Ok(())` - Successfully marked
    /// * `Err(anyhow::Error)` - Intent not found
    pub async fn mark_fulfilled(&self, draft_id: &str) -> Result<()> {
        let mut intents = self.intents.write().await;
        if let Some(intent) = intents.get_mut(draft_id) {
            intent.state = IntentState::Fulfilled;
            Ok(())
        } else {
            anyhow::bail!("Intent not found: {}", draft_id)
        }
    }

    /// Gets a tracked intent by draft ID
    ///
    /// # Note
    /// This method is primarily for testing. In production, use `get_intents_ready_for_fulfillment()`.
    pub async fn get_intent(&self, draft_id: &str) -> Option<TrackedIntent> {
        let intents = self.intents.read().await;
        intents.get(draft_id).cloned()
    }

    /// Manually sets intent state
    ///
    /// # Note
    /// This method is primarily for testing. In production, state transitions happen via `poll_for_created_intents()`.
    pub async fn set_intent_state(&self, draft_id: &str, state: IntentState) -> Result<()> {
        let mut intents = self.intents.write().await;
        if let Some(intent) = intents.get_mut(draft_id) {
            intent.state = state;
            Ok(())
        } else {
            anyhow::bail!("Intent not found: {}", draft_id)
        }
    }
}

/// Normalize intent ID for comparison (strip 0x prefix, pad to 64 hex chars)
fn normalize_intent_id(intent_id: &str) -> String {
    let cleaned = intent_id.strip_prefix("0x").unwrap_or(intent_id);
    format!("0x{:0>64}", cleaned)
}

