//! Inflow validation API handlers (chain-agnostic)
//!
//! This module handles API endpoints for inflow intent validation.
//! Inflow intents have tokens locked on the connected chain (in escrow) and request tokens on the hub chain.
//!
//! The validation flow:
//! 1. Solver creates escrow on connected chain (tokens locked)
//! 2. Verifier monitors hub chain for fulfillment event
//! 3. When hub fulfillment is observed, verifier validates escrow matches intent
//! 4. Verifier generates approval signature for connected chain escrow release
//! 5. Solver uses signature to release escrow on connected chain
//!
//! Note: Inflow validation is primarily automatic via the event monitor, but this module
//! provides API endpoints for manual validation and signature retrieval.

use anyhow::Result;
use serde::Deserialize;
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::api::generic::ApiResponse;
use crate::monitor::EventMonitor;

// ============================================================================
// REQUEST/RESPONSE STRUCTURES
// ============================================================================

/// Request structure for validating inflow escrow deposits.
///
/// This structure contains the escrow ID needed to validate an escrow deposit
/// on the connected chain for an inflow intent.
#[derive(Debug, Deserialize)]
pub struct ValidateInflowEscrowRequest {
    /// Escrow ID on the connected chain
    pub escrow_id: String,
    /// Chain type: "mvm" or "evm" (currently unused, reserved for future use)
    #[allow(dead_code)]
    pub chain_type: String,
}

// ============================================================================
// API HANDLERS
// ============================================================================

/// Handler for the validate-inflow-escrow endpoint.
///
/// This function validates an escrow deposit on the connected chain for an inflow intent.
/// The validation checks that the escrow matches the hub request intent requirements.
///
/// Note: Inflow validation is typically automatic via the event monitor when hub
/// fulfillment is observed. This endpoint provides manual validation capability.
///
/// # Arguments
///
/// * `request` - The validation request containing escrow ID and chain type
/// * `monitor` - The event monitor instance
///
/// # Returns
///
/// * `Ok(warp::Reply)` - JSON response with validation result
/// * `Err(warp::Rejection)` - Failed to validate escrow
pub async fn handle_inflow_escrow_validation(
    request: ValidateInflowEscrowRequest,
    monitor: Arc<RwLock<EventMonitor>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let monitor = monitor.read().await;

    // Find escrow in cache
    let escrow_events = monitor.get_cached_escrow_events().await;
    let escrow = match escrow_events
        .iter()
        .find(|e| e.escrow_id == request.escrow_id)
    {
        Some(escrow) => escrow.clone(),
        None => {
            return Ok(warp::reply::json(&ApiResponse::<
                crate::validator::ValidationResult,
            > {
                success: false,
                data: None,
                error: Some(format!("Escrow not found: {}", request.escrow_id)),
            }));
        }
    };

    // Validate escrow against request intent
    // This uses the same validation logic as the automatic monitor validation
    match monitor.validate_request_intent_fulfillment(&escrow).await {
        Ok(()) => Ok(warp::reply::json(&ApiResponse {
            success: true,
            data: Some(crate::validator::ValidationResult {
                valid: true,
                message: "Escrow validation successful".to_string(),
                timestamp: chrono::Utc::now().timestamp() as u64,
            }),
            error: None,
        })),
        Err(e) => Ok(warp::reply::json(&ApiResponse::<
            crate::validator::ValidationResult,
        > {
            success: false,
            data: Some(crate::validator::ValidationResult {
                valid: false,
                message: format!("Escrow validation failed: {}", e),
                timestamp: chrono::Utc::now().timestamp() as u64,
            }),
            error: Some(format!("Validation failed: {}", e)),
        })),
    }
}
