//! Generic monitor structures and EventMonitor definition
//!
//! This module contains shared event structures and the EventMonitor struct definition
//! that are used across all flow types (inflow/outflow) and chain types (Move VM/EVM).

use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::config::Config;
use crate::crypto::CryptoService;
use crate::validator::CrossChainValidator;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Normalizes an intent ID by removing leading zeros after the 0x prefix and converting to lowercase.
///
/// This ensures that intent IDs like "0x0911..." and "0x911..." are treated as the same value.
///
/// # Arguments
///
/// * `intent_id` - The intent ID to normalize (e.g., "0x0911..." or "0x911...")
///
/// # Returns
///
/// * Normalized intent ID with 0x prefix, no leading zeros, lowercase (e.g., "0x911...")
pub fn normalize_intent_id(intent_id: &str) -> String {
    let stripped = intent_id.strip_prefix("0x").unwrap_or(intent_id);
    // Remove leading zeros
    let trimmed = stripped.trim_start_matches('0');
    // If all zeros, keep at least one zero
    let hex_part = if trimmed.is_empty() { "0" } else { trimmed };
    format!("0x{}", hex_part.to_lowercase())
}

/// Normalizes an intent ID to 64 hex characters (32 bytes) by padding with leading zeros.
///
/// This ensures that intent IDs can be safely parsed as hex, even if they have an odd number
/// of hex characters or are shorter than 64 characters.
///
/// # Arguments
///
/// * `intent_id` - The intent ID to normalize (e.g., "0xabc..." or "0x0abc...")
///
/// # Returns
///
/// * Normalized intent ID with 0x prefix, padded to 64 hex characters, lowercase
pub fn normalize_intent_id_to_64_chars(intent_id: &str) -> String {
    let stripped = intent_id.strip_prefix("0x").unwrap_or(intent_id);
    format!("0x{:0>64}", stripped.to_lowercase())
}

// ============================================================================
// EVENT DATA STRUCTURES
// ============================================================================

/// Type of blockchain where an escrow or intent is located.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChainType {
    /// Move VM-based chain (e.g., Aptos)
    Mvm,
    /// EVM-compatible chain (e.g., Ethereum, Polygon, Arbitrum)
    Evm,
    /// Solana chain
    Svm,
}

/// Request-intent creation event from the hub chain.
///
/// This event is emitted when a new intent is created on the hub chain.
/// The verifier monitors these events to track new trading opportunities
/// and validate their safety for escrow operations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentEvent {
    /// Unique identifier for the intent
    pub intent_id: String,
    /// Address of the requester who created the intent
    pub requester: String,
    /// Metadata of the asset being offered
    pub offered_metadata: String,
    /// Amount of the asset being offered (u64, matching Move contract constraint)
    pub offered_amount: u64,
    /// Metadata of the desired asset
    pub desired_metadata: String,
    /// Amount of the desired asset (u64, matching Move contract constraint)
    pub desired_amount: u64,
    /// Unix timestamp when the intent expires
    pub expiry_time: u64,
    /// Whether the intent can be revoked by the creator
    pub revocable: bool,
    /// Solver address if the intent is reserved (None for unreserved intents)
    pub reserved_solver: Option<String>,
    /// Connected chain ID where escrow will be created (None for regular intents)
    pub connected_chain_id: Option<u64>,
    /// Requester address on connected chain (for outflow intents - where solver should send tokens)
    /// None for inflow intents or if not available
    pub requester_address_connected_chain: Option<String>,
    /// Timestamp when the event was received
    pub timestamp: u64,
}

/// Escrow deposit event from the connected chain.
///
/// This event is emitted when a solver deposits assets into an escrow
/// on the connected chain. The verifier validates that this deposit
/// fulfills the conditions specified in the original intent.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EscrowEvent {
    /// Unique identifier for the escrow (on connected chain)
    pub escrow_id: String,
    /// Unique identifier for the intent on hub chain (for matching)
    pub intent_id: String,
    /// Address of the issuer who created the escrow (who locked the funds)
    pub issuer: String,
    /// Metadata of the asset being offered (what's locked in escrow)
    pub offered_metadata: String,
    /// Amount of the asset being offered (u64, matching Move contract constraint)
    pub offered_amount: u64,
    /// Metadata of the desired asset (what solver needs to provide)
    pub desired_metadata: String,
    /// Amount of the desired asset (u64, matching Move contract constraint)
    pub desired_amount: u64,
    /// Unix timestamp when the escrow expires
    pub expiry_time: u64,
    /// Whether the escrow intent can be revoked (should always be false for security)
    pub revocable: bool,
    /// Reserved solver address if the escrow is reserved (None for unreserved escrows)
    /// For Move VM escrows: Move VM address
    /// For EVM escrows: EVM address (0x-prefixed hex string)
    pub reserved_solver: Option<String>,
    /// Chain ID where this escrow is located
    /// Note: This is set by the verifier based on which monitor discovered the event (from config),
    /// not from the event data itself, so it can be trusted for validation.
    pub chain_id: u64,
    /// Type of blockchain where this escrow is located
    /// Note: This is set by the verifier based on which monitor discovered the event,
    /// not from the event data itself, so it can be trusted for validation.
    pub chain_type: ChainType,
    /// Timestamp when the event was received
    pub timestamp: u64,
}

/// Fulfillment event from the hub chain.
///
/// This event is emitted when a intent is fulfilled by a solver.
/// The verifier monitors these events to track when hub intents are completed,
/// which triggers the approval workflow for escrow release on the connected chain.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FulfillmentEvent {
    /// Unique identifier for the intent that was fulfilled
    pub intent_id: String,
    /// Address of the intent that was fulfilled
    pub intent_address: String,
    /// Address of the solver who fulfilled the intent
    pub solver: String,
    /// Metadata of the asset provided by the solver
    pub provided_metadata: String,
    /// Amount of the asset provided by the solver (u64, matching Move contract constraint)
    pub provided_amount: u64,
    /// Unix timestamp when the intent was fulfilled
    pub timestamp: u64,
}

/// Approval signature for escrow release
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EscrowApproval {
    /// Escrow ID for which this approval was generated
    pub escrow_id: String,
    /// Intent ID that links hub and connected chain
    pub intent_id: String,
    /// Signature bytes (base64 encoded) - signature itself is the approval
    pub signature: String,
    /// Timestamp when approval was generated
    pub timestamp: u64,
}

// ============================================================================
// EVENT MONITOR STRUCTURE
// ============================================================================

/// Event monitor that watches both hub and connected chains for relevant events.
///
/// This monitor runs continuously, polling both chains for new events and
/// processing them according to the verifier's validation rules. It maintains
/// an in-memory cache of recent events for API access.
#[derive(Clone)]
pub struct EventMonitor {
    /// Service configuration
    pub config: Arc<Config>,
    /// HTTP client for hub chain communication
    #[allow(dead_code)]
    pub hub_client: reqwest::Client,
    /// HTTP client for connected chain communication
    #[allow(dead_code)]
    pub connected_client: reqwest::Client,
    /// Cross-chain validator for validation logic
    pub validator: Arc<CrossChainValidator>,
    /// Cryptographic operations for signature generation
    pub crypto: Arc<CryptoService>,
    /// In-memory cache of recent intent events
    ///
    /// **WARNING**: This field is public ONLY for unit testing purposes.
    /// It should not be accessed directly in production code.
    #[doc(hidden)]
    pub event_cache: Arc<RwLock<Vec<IntentEvent>>>,
    /// In-memory cache of recent escrow events
    ///
    /// **WARNING**: This field is public ONLY for unit testing purposes.
    /// It should not be accessed directly in production code.
    #[doc(hidden)]
    pub escrow_cache: Arc<RwLock<Vec<EscrowEvent>>>,
    /// In-memory cache of fulfillment events
    ///
    /// **WARNING**: This field is public ONLY for unit testing purposes.
    /// It should not be accessed directly in production code.
    #[doc(hidden)]
    pub fulfillment_cache: Arc<RwLock<Vec<FulfillmentEvent>>>,
    /// In-memory cache of approval signatures for escrow release
    pub approval_cache: Arc<RwLock<Vec<EscrowApproval>>>,
}

impl EventMonitor {
    /// Creates a new event monitor with the given configuration.
    ///
    /// This function initializes HTTP clients with appropriate timeouts
    /// and prepares the event cache for use.
    ///
    /// # Arguments
    ///
    /// * `config` - Service configuration containing chain URLs and timeouts
    ///
    /// # Returns
    ///
    /// * `Ok(EventMonitor)` - Successfully created monitor
    /// * `Err(anyhow::Error)` - Failed to create monitor
    pub async fn new(config: &Config) -> anyhow::Result<Self> {
        use crate::crypto::CryptoService;
        use crate::validator::CrossChainValidator;

        // Create HTTP client for hub chain with configured timeout
        let hub_client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_millis(
                config.verifier.validation_timeout_ms,
            ))
            .build()?;

        // Create HTTP client for connected chain with configured timeout
        let connected_client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_millis(
                config.verifier.validation_timeout_ms,
            ))
            .build()?;

        // Create validator and crypto instances
        let validator = Arc::new(CrossChainValidator::new(config).await?);
        let crypto = Arc::new(CryptoService::new(config)?);

        Ok(Self {
            config: Arc::new(config.clone()),
            hub_client,
            connected_client,
            validator,
            crypto,
            event_cache: Arc::new(RwLock::new(Vec::new())),
            escrow_cache: Arc::new(RwLock::new(Vec::new())),
            fulfillment_cache: Arc::new(RwLock::new(Vec::new())),
            approval_cache: Arc::new(RwLock::new(Vec::new())),
        })
    }

    /// Starts the event monitoring process for configured chains.
    ///
    /// This function runs monitoring loops:
    /// 1. Hub chain monitoring for intent events (always)
    /// 2. Connected Move VM chain monitoring for escrow events (if configured)
    /// 3. Connected EVM chain monitoring for escrow events (if configured)
    ///
    /// The function blocks until all monitors complete (which should be never
    /// in normal operation, as they run infinite loops).
    ///
    /// # Returns
    ///
    /// * `Ok(())` - Monitoring started successfully
    /// * `Err(anyhow::Error)` - Failed to start monitoring
    pub async fn start_monitoring(&self) -> anyhow::Result<()> {
        use super::inflow_generic;
        use super::outflow_generic;
        use tracing::info;

        info!("Starting event monitoring");

        // Start hub chain monitoring (always required) - for outflow intents
        let hub_monitor = outflow_generic::monitor_hub_chain(self);

        // Conditionally start connected Move VM chain monitoring if configured - for inflow intents
        if let Some(_) = &self.config.connected_chain_mvm {
            info!("Connected Move VM chain configured, starting connected chain monitoring");
            let mvm_monitor = inflow_generic::monitor_connected_chain(self);
            let evm_monitor = if let Some(_) = &self.config.connected_chain_evm {
                info!("Connected EVM chain configured, starting EVM chain monitoring");
                Some(inflow_generic::monitor_evm_chain(self))
            } else {
                info!("No connected EVM chain configured");
                None
            };

            // Run all monitors concurrently
            if let Some(evm) = evm_monitor {
                tokio::try_join!(hub_monitor, mvm_monitor, evm)?;
            } else {
                tokio::try_join!(hub_monitor, mvm_monitor)?;
            }
        } else if let Some(_) = &self.config.connected_chain_evm {
            info!("Connected EVM chain configured, starting EVM chain monitoring");
            let evm_monitor = inflow_generic::monitor_evm_chain(self);
            tokio::try_join!(hub_monitor, evm_monitor)?;
        } else {
            info!("No connected chains configured, monitoring hub chain only");
            hub_monitor.await?;
        }

        Ok(())
    }

    /// Polls the hub chain for new intent events.
    ///
    /// This function queries the hub chain's event logs for new intent
    /// creation events. Since module events are emitted in user transactions,
    /// we query known test accounts for their events.
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<IntentEvent>)` - List of new intent events
    /// * `Err(anyhow::Error)` - Failed to poll events
    #[allow(dead_code)]
    pub async fn poll_hub_events(&self) -> anyhow::Result<Vec<IntentEvent>> {
        use super::outflow_generic;
        outflow_generic::poll_hub_events(self).await
    }

    /// Polls connected chains for new escrow events.
    ///
    /// This function queries connected chains (Move VM and/or EVM) for escrow initialization
    /// events. It handles both Move VM and EVM chains if configured.
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<EscrowEvent>)` - List of new escrow events from all connected chains
    /// * `Err(anyhow::Error)` - Failed to poll events
    #[allow(dead_code)]
    pub async fn poll_connected_events(&self) -> anyhow::Result<Vec<EscrowEvent>> {
        use super::inflow_generic;
        inflow_generic::poll_connected_events(self).await
    }

    /// Validates that an escrow event fulfills the conditions of an existing intent.
    ///
    /// This function checks whether the escrow deposit matches the requirements
    /// specified in a previously created intent. It ensures that the solver
    /// has provided the correct asset type and amount.
    ///
    /// # Arguments
    ///
    /// * `escrow_event` - The escrow deposit event to validate
    ///
    /// # Returns
    ///
    /// * `Ok(())` - Validation successful
    /// * `Err(anyhow::Error)` - Validation failed
    /// Note: Public for testing purposes
    #[doc(hidden)]
    pub async fn validate_intent_fulfillment(
        &self,
        escrow_event: &EscrowEvent,
    ) -> anyhow::Result<()> {
        use super::inflow_generic;
        inflow_generic::validate_intent_fulfillment(self, escrow_event).await
    }

    /// Returns a copy of all cached intent events.
    ///
    /// This function provides access to the event cache for API endpoints
    /// and external monitoring systems.
    ///
    /// # Returns
    ///
    /// A vector containing all cached intent events
    pub async fn get_cached_events(&self) -> Vec<IntentEvent> {
        use super::outflow_generic;
        outflow_generic::get_cached_events(self).await
    }

    /// Returns a copy of all cached escrow events.
    ///
    /// This function provides access to the escrow event cache for API endpoints
    /// and external monitoring systems.
    ///
    /// # Returns
    ///
    /// A vector containing all cached escrow events
    pub async fn get_cached_escrow_events(&self) -> Vec<EscrowEvent> {
        use super::inflow_generic;
        inflow_generic::get_cached_escrow_events(self).await
    }

    /// Returns a copy of all cached fulfillment events.
    ///
    /// This function provides access to the fulfillment event cache for API endpoints.
    ///
    /// # Returns
    ///
    /// A vector containing all cached fulfillment events
    pub async fn get_cached_fulfillment_events(&self) -> Vec<FulfillmentEvent> {
        use super::outflow_generic;
        outflow_generic::get_cached_fulfillment_events(self).await
    }

    /// Generates approval signature after fulfillment is observed.
    ///
    /// This function:
    /// 1. Confirms fulfillment event exists (Move already validated fulfillment conditions)
    /// 2. Confirms matching escrow exists (verifier already validated escrow earlier)
    /// 3. Generates approval signature for escrow release
    ///
    /// Note: We don't validate here because:
    /// - Fulfillment validity: Move contract only emits fulfillment events when conditions are correct
    /// - Escrow validity: Verifier validates escrow before solver fulfills (future: provides signature to solver)
    /// - By the time we see fulfillment, both were already validated
    ///
    /// # Arguments
    ///
    /// * `fulfillment` - The fulfillment event that was observed
    ///
    /// # Returns
    ///
    /// * `Ok(())` - Approval generated successfully
    /// * `Err(anyhow::Error)` - Failed to generate approval (e.g., missing escrow)
    ///
    /// Note: Public for testing purposes
    #[doc(hidden)]
    #[allow(dead_code)]
    pub async fn validate_and_approve_fulfillment(
        &self,
        fulfillment: &FulfillmentEvent,
    ) -> anyhow::Result<()> {
        use super::inflow_generic;
        inflow_generic::validate_and_approve_fulfillment(self, fulfillment).await
    }

    /// Returns a copy of all cached approval signatures.
    ///
    /// This function provides access to the approval cache for API endpoints
    /// and escrow release operations.
    ///
    /// # Returns
    ///
    /// A vector containing all cached approval signatures
    pub async fn get_cached_approvals(&self) -> Vec<EscrowApproval> {
        use super::inflow_generic;
        inflow_generic::get_cached_approvals(self).await
    }

    /// Gets approval signature for a specific escrow.
    ///
    /// # Arguments
    ///
    /// * `escrow_id` - The escrow ID to look up
    ///
    /// # Returns
    ///
    /// * `Some(EscrowApproval)` - Approval signature if found
    /// * `None` - No approval found for this escrow
    pub async fn get_approval_for_escrow(&self, escrow_id: &str) -> Option<EscrowApproval> {
        use super::inflow_generic;
        inflow_generic::get_approval_for_escrow(self, escrow_id).await
    }
}
