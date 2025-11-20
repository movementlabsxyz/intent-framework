//! Inflow-specific monitor helpers (chain-agnostic)
//!
//! This module handles connected-chain escrow monitoring, validation, and approval generation
//! for inflow intents. Inflow intents have tokens locked on the connected chain (in escrow)
//! and request tokens on the hub chain.
//!
//! ## Flow Overview
//!
//! 1. Solver creates escrow on connected chain (tokens locked in escrow)
//! 2. Verifier monitors connected chain for escrow events
//! 3. Verifier validates escrow matches hub request intent requirements
//! 4. Verifier monitors hub chain for fulfillment events
//! 5. When hub fulfillment is observed, verifier generates approval signature for escrow release
//! 6. Solver uses signature to release escrow on connected chain
//!
//! ## Security Requirements
//!
//! **CRITICAL**: Escrow validation ensures that:
//! - Escrow amount matches or exceeds intent desired amount
//! - Escrow metadata matches intent desired metadata
//! - Solver addresses match (if intent is reserved)
//! - Intent has not expired

use anyhow::Result;
use base64::{engine::general_purpose, Engine as _};
use tracing::{error, info};

use super::generic::{EscrowApproval, EscrowEvent, EventMonitor, FulfillmentEvent};
use super::inflow_evm;
use super::inflow_mvm;

// ============================================================================
// CONNECTED CHAIN MONITORING
// ============================================================================

/// Monitors the connected Move VM chain for escrow deposit events.
///
/// This function runs in an infinite loop, polling the connected Move VM chain
/// for escrow deposit events. When events are found, it caches them and validates
/// that they fulfill the conditions of existing hub request intents.
///
/// The validation ensures that:
/// - Escrow amount matches or exceeds intent desired amount
/// - Escrow metadata matches intent desired metadata
/// - Solver addresses match (if intent is reserved)
/// - Intent has not expired
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
///
/// # Returns
///
/// * `Ok(())` - Monitoring started successfully (runs indefinitely)
/// * `Err(anyhow::Error)` - Failed to start monitoring
///
/// # Behavior
///
/// Returns early if no connected Move VM chain is configured.
pub async fn monitor_connected_chain(monitor: &EventMonitor) -> Result<()> {
    let connected_chain_mvm = match &monitor.config.connected_chain_mvm {
        Some(chain) => chain,
        None => {
            info!("No connected Move VM chain configured, skipping connected chain monitoring");
            return Ok(());
        }
    };

    info!(
        "Starting connected Move VM chain monitoring for escrow events on {}",
        connected_chain_mvm.name
    );

    loop {
        match inflow_mvm::poll_mvm_escrow_events(&monitor.config).await {
            Ok(events) => {
                for event in events {
                    info!("Received escrow event: {:?}", event);

                    {
                        let escrow_id = event.escrow_id.clone();
                        let chain_id = event.chain_id;
                        let mut escrow_cache = monitor.escrow_cache.write().await;
                        if !escrow_cache.iter().any(|cached| {
                            cached.escrow_id == escrow_id && cached.chain_id == chain_id
                        }) {
                            escrow_cache.push(event.clone());
                        }
                    }

                    // Validate that this escrow fulfills an existing request intent
                    // Note: It's normal for escrow to exist before request intent (escrow created first)
                    if let Err(e) = validate_request_intent_fulfillment(monitor, &event).await {
                        // If no matching request intent found, just log info (request intent may be created later)
                        if e.to_string().contains("No matching request intent found") {
                            info!("Registered escrow {} for intent_id {} (request intent not yet created on hub chain)", event.escrow_id, event.intent_id);
                        } else {
                            error!("Intent fulfillment validation failed: {}", e);
                        }
                    }
                }
            }
            Err(e) => {
                error!("Error polling connected events: {}", e);
            }
        }

        tokio::time::sleep(std::time::Duration::from_millis(
            monitor.config.verifier.polling_interval_ms,
        ))
        .await;
    }
}

/// Monitors the connected EVM chain for escrow initialization events.
///
/// This function runs in an infinite loop, polling the connected EVM chain
/// for EscrowInitialized events. When events are found, it caches them and validates
/// that they fulfill the conditions of existing hub request intents.
///
/// The validation ensures that:
/// - Escrow amount matches or exceeds intent desired amount
/// - Escrow metadata matches intent desired metadata
/// - Solver addresses match (if intent is reserved)
/// - Intent has not expired
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
///
/// # Returns
///
/// * `Ok(())` - Monitoring started successfully (runs indefinitely)
/// * `Err(anyhow::Error)` - Failed to start monitoring
///
/// # Behavior
///
/// Returns early if no connected EVM chain is configured.
pub async fn monitor_evm_chain(monitor: &EventMonitor) -> Result<()> {
    let connected_chain_evm = match &monitor.config.connected_chain_evm {
        Some(chain) => chain,
        None => {
            info!("No connected EVM chain configured, skipping EVM chain monitoring");
            return Ok(());
        }
    };

    info!(
        "Starting connected EVM chain monitoring for escrow events on {}",
        connected_chain_evm.name
    );

    loop {
        match inflow_evm::poll_evm_escrow_events(&monitor.config).await {
            Ok(events) => {
                for event in events {
                    info!("Received EVM escrow event: {:?}", event);

                    // Cache the escrow event (deduplicate by escrow_id + chain_id)
                    {
                        let escrow_id = event.escrow_id.clone();
                        let chain_id = event.chain_id;
                        let mut escrow_cache = monitor.escrow_cache.write().await;
                        if !escrow_cache.iter().any(|cached| {
                            cached.escrow_id == escrow_id && cached.chain_id == chain_id
                        }) {
                            escrow_cache.push(event.clone());
                        }
                    }

                    // Validate that this escrow fulfills an existing request intent
                    // Note: It's normal for escrow to exist before request intent (escrow created first)
                    if let Err(e) = validate_request_intent_fulfillment(monitor, &event).await {
                        // If no matching request intent found, just log info (request intent may be created later)
                        if e.to_string().contains("No matching request intent found") {
                            info!("Registered escrow {} for intent_id {} (request intent not yet created on hub chain)", event.escrow_id, event.intent_id);
                        } else {
                            error!("Intent fulfillment validation failed for EVM escrow: {}", e);
                        }
                    }
                }
            }
            Err(e) => {
                error!("Error polling connected EVM events: {:#}", e);
            }
        }

        tokio::time::sleep(std::time::Duration::from_millis(
            monitor.config.verifier.polling_interval_ms,
        ))
        .await;
    }
}

// ============================================================================
// EVENT POLLING
// ============================================================================

/// Polls connected chains for new escrow events.
///
/// This function queries connected chains (Move VM and/or EVM) for escrow initialization
/// events. It handles both Move VM and EVM chains if configured, aggregating events
/// from all connected chains into a single vector.
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
///
/// # Returns
///
/// * `Ok(Vec<EscrowEvent>)` - List of new escrow events from all connected chains
/// * `Err(anyhow::Error)` - Failed to poll events from one or more chains
///
/// # Behavior
///
/// If polling fails for one chain, the function continues to poll other chains
/// and returns events from successfully polled chains. Errors are logged but
/// do not cause the function to fail.
#[allow(dead_code)]
pub async fn poll_connected_events(monitor: &EventMonitor) -> Result<Vec<EscrowEvent>> {
    let mut escrow_events = Vec::new();

    if let Some(_) = &monitor.config.connected_chain_mvm {
        match inflow_mvm::poll_mvm_escrow_events(&monitor.config).await {
            Ok(mut events) => {
                escrow_events.append(&mut events);
            }
            Err(e) => {
                error!("Failed to poll Move VM escrow events: {}", e);
            }
        }
    }

    if let Some(_) = &monitor.config.connected_chain_evm {
        match inflow_evm::poll_evm_escrow_events(&monitor.config).await {
            Ok(mut events) => {
                escrow_events.append(&mut events);
            }
            Err(e) => {
                error!("Failed to poll EVM escrow events: {}", e);
            }
        }
    }

    Ok(escrow_events)
}

// ============================================================================
// VALIDATION
// ============================================================================

/// Validates that an escrow event fulfills the conditions of an existing request intent.
///
/// This function checks whether the escrow deposit matches the requirements
/// specified in a previously created hub request intent. It ensures that the solver
/// has provided the correct asset type and amount, and that all other conditions are met.
///
/// ## Validation Checks
///
/// 1. **Amount Check**: Escrow offered_amount must be >= intent desired_amount
/// 2. **Metadata Check**: Escrow desired_metadata must match intent desired_metadata
/// 3. **Solver Check**: Solver addresses must match (if intent is reserved)
/// 4. **Expiry Check**: Intent must not have expired
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
/// * `escrow_event` - The escrow deposit event to validate
///
/// # Returns
///
/// * `Ok(())` - Validation successful, escrow fulfills intent requirements
/// * `Err(anyhow::Error)` - Validation failed with specific error message
///
/// # Errors
///
/// Returns an error if:
/// - No matching request intent is found for the escrow's intent_id
/// - Escrow amount is less than required amount
/// - Escrow metadata does not match desired metadata
/// - Solver addresses do not match (for reserved intents)
/// - Request intent has expired
pub async fn validate_request_intent_fulfillment(
    monitor: &EventMonitor,
    escrow_event: &EscrowEvent,
) -> Result<()> {
    info!(
        "Validating request intent fulfillment for escrow: {} (intent_id: {})",
        escrow_event.escrow_id, escrow_event.intent_id
    );

    let cache = monitor.event_cache.read().await;
    // Normalize intent IDs for comparison (handles leading zero differences)
    let escrow_intent_id_normalized =
        crate::monitor::generic::normalize_intent_id(&escrow_event.intent_id);
    let matching_request_intent = cache.iter().find(|request_intent| {
        crate::monitor::generic::normalize_intent_id(&request_intent.intent_id)
            == escrow_intent_id_normalized
    });

    match matching_request_intent {
        Some(request_intent) => {
            info!(
                "Found matching request intent: {} for escrow: {}",
                request_intent.intent_id, escrow_event.escrow_id
            );

            if escrow_event.offered_amount < request_intent.desired_amount {
                return Err(anyhow::anyhow!(
                    "Deposit amount {} is less than required amount {}",
                    escrow_event.offered_amount,
                    request_intent.desired_amount
                ));
            }

            if escrow_event.desired_metadata != request_intent.desired_metadata {
                return Err(anyhow::anyhow!(
                    "Deposit metadata {} does not match desired metadata {}",
                    escrow_event.desired_metadata,
                    request_intent.desired_metadata
                ));
            }

            let validation_result =
                crate::validator::inflow_generic::validate_request_intent_fulfillment(
                    &monitor.validator,
                    request_intent,
                    escrow_event,
                )
                .await?;
            if !validation_result.valid {
                return Err(anyhow::anyhow!(
                    "Solver validation failed: {}",
                    validation_result.message
                ));
            }

            let current_time = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_secs();

            if current_time > request_intent.expiry_time {
                return Err(anyhow::anyhow!(
                    "Request intent {} has expired (expiry: {}, current: {})",
                    request_intent.intent_id,
                    request_intent.expiry_time,
                    current_time
                ));
            }

            info!(
                "Validation successful for escrow: {}",
                escrow_event.escrow_id
            );
            Ok(())
        }
        None => Err(anyhow::anyhow!(
            "No matching request intent found for escrow: {} (intent_id: {})",
            escrow_event.escrow_id,
            escrow_event.intent_id
        )),
    }
}

/// Generates approval signature after hub fulfillment is observed.
///
/// This function is called when a fulfillment event is observed on the hub chain
/// for an inflow intent. It:
/// 1. Confirms matching escrow exists in cache (escrow was already validated earlier)
/// 2. Generates approval signature for escrow release on connected chain
/// 3. Stores the approval signature in cache for API access
///
/// ## Signature Generation
///
/// - **Move VM escrows**: Ed25519 signature (signed with intent_id)
/// - **EVM escrows**: ECDSA signature (signed with intent_id, base64 encoded)
///
/// ## Security Notes
///
/// We don't re-validate here because:
/// - **Fulfillment validity**: Move contract only emits fulfillment events when conditions are correct
/// - **Escrow validity**: Verifier validates escrow before solver fulfills (when escrow was cached)
/// - **By the time we see fulfillment, both were already validated**
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
/// * `fulfillment` - The fulfillment event that was observed on the hub chain
///
/// # Returns
///
/// * `Ok(())` - Approval generated successfully
/// * `Err(anyhow::Error)` - Failed to generate approval (e.g., missing escrow)
///
/// # Errors
///
/// Returns an error if no matching escrow is found for the fulfillment's intent_id.
/// This should not happen in normal operation, as escrows are validated and cached
/// before hub fulfillment occurs.
pub async fn validate_and_approve_fulfillment(
    monitor: &EventMonitor,
    fulfillment: &FulfillmentEvent,
) -> Result<()> {
    let escrow_cache = monitor.escrow_cache.read().await;
    // Normalize intent IDs for comparison (handles leading zero differences)
    let fulfillment_intent_id_normalized =
        crate::monitor::generic::normalize_intent_id(&fulfillment.intent_id);
    let matching_escrow = escrow_cache.iter().find(|escrow| {
        crate::monitor::generic::normalize_intent_id(&escrow.intent_id)
            == fulfillment_intent_id_normalized
    });

    // Find matching escrow in cache
    let (escrow_id, is_evm_escrow) = match matching_escrow {
        Some(escrow) => {
            // Determine if this is an EVM escrow by checking if reserved_solver looks like an EVM address
            let is_evm = escrow
                .reserved_solver
                .as_ref()
                .map(|s| s.starts_with("0x") && s.len() == 42)
                .unwrap_or(false);

            let escrow_id = escrow.escrow_id.clone();
            drop(escrow_cache);
            (escrow_id, is_evm)
        }
        None => {
            drop(escrow_cache);
            error!(
                "No matching escrow found for fulfillment: {} (intent_id: {})",
                fulfillment.intent_address, fulfillment.intent_id
            );
            return Err(anyhow::anyhow!("No matching escrow found for fulfillment"));
        }
    };

    info!(
        "Generating approval after fulfillment observed: intent_id {} (escrow_id: {})",
        fulfillment.intent_id, escrow_id
    );

    // Generate signature based on escrow chain type
    let (signature_bytes, timestamp) = if is_evm_escrow {
        // EVM escrow: Create ECDSA signature
        info!(
            "Creating ECDSA signature for EVM escrow (intent_id: {})",
            fulfillment.intent_id
        );
        let intent_id_hex = fulfillment
            .intent_id
            .strip_prefix("0x")
            .unwrap_or(&fulfillment.intent_id);
        let ecdsa_sig_bytes = monitor
            .crypto
            .create_evm_approval_signature(intent_id_hex)?;
        // Convert bytes to base64 for storage (EscrowApproval expects String)
        let signature_base64 = general_purpose::STANDARD.encode(&ecdsa_sig_bytes);
        (signature_base64, chrono::Utc::now().timestamp() as u64)
    } else {
        // Move VM escrow: Create Ed25519 signature
        info!(
            "Creating Ed25519 signature for Move VM escrow (escrow_id: {}, intent_id: {})",
            escrow_id, fulfillment.intent_id
        );
        let approval_sig = monitor
            .crypto
            .create_mvm_approval_signature(&fulfillment.intent_id)?;
        (approval_sig.signature, approval_sig.timestamp)
    };

    // Store approval signature in cache (deduplicate by escrow_id)
    {
        let mut approval_cache = monitor.approval_cache.write().await;
        if !approval_cache
            .iter()
            .any(|approval| approval.escrow_id == escrow_id)
        {
            approval_cache.push(EscrowApproval {
                escrow_id: escrow_id.clone(),
                intent_id: fulfillment.intent_id.clone(),
                signature: signature_bytes,
                timestamp,
            });

            info!(
                "✅ Generated {} approval signature for escrow: {} (intent_id: {})",
                if is_evm_escrow { "ECDSA" } else { "Ed25519" },
                escrow_id,
                fulfillment.intent_id
            );
        } else {
            info!(
                "Approval signature already exists for escrow: {}",
                escrow_id
            );
        }
    }

    Ok(())
}

// ============================================================================
// CACHE ACCESS
// ============================================================================

/// Returns a copy of all cached escrow events.
///
/// This function provides access to the escrow event cache for API endpoints
/// and external monitoring systems. The cache contains all escrow events that
/// have been observed on connected chains (both Move VM and EVM).
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
///
/// # Returns
///
/// A vector containing all cached escrow events from all connected chains
pub async fn get_cached_escrow_events(monitor: &EventMonitor) -> Vec<EscrowEvent> {
    monitor.escrow_cache.read().await.clone()
}

/// Returns a copy of all cached approval signatures.
///
/// This function provides access to the approval cache for API endpoints
/// and escrow release operations. The cache contains approval signatures that
/// have been generated after hub fulfillment events were observed.
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
///
/// # Returns
///
/// A vector containing all cached approval signatures
pub async fn get_cached_approvals(monitor: &EventMonitor) -> Vec<EscrowApproval> {
    monitor.approval_cache.read().await.clone()
}

/// Gets approval signature for a specific escrow.
///
/// This function looks up an approval signature by escrow ID. Approval signatures
/// are generated automatically when hub fulfillment events are observed for
/// matching escrows.
///
/// # Arguments
///
/// * `monitor` - The event monitor instance
/// * `escrow_id` - The escrow ID to look up
///
/// # Returns
///
/// * `Some(EscrowApproval)` - Approval signature if found
/// * `None` - No approval found for this escrow (fulfillment not yet observed or escrow doesn't exist)
pub async fn get_approval_for_escrow(
    monitor: &EventMonitor,
    escrow_id: &str,
) -> Option<EscrowApproval> {
    let approvals = monitor.approval_cache.read().await;
    approvals
        .iter()
        .find(|approval| approval.escrow_id == escrow_id)
        .cloned()
}
