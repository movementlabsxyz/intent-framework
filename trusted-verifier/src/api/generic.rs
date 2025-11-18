//! Generic API structures and handlers
//!
//! This module contains shared structures, helper functions, and generic API handlers
//! that are used across all flow types (inflow/outflow) and chain types (Aptos/EVM).

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use warp::Filter;

use crate::monitor::EventMonitor;
use crate::crypto::CryptoService;
use crate::validator::CrossChainValidator;

// ============================================================================
// SHARED REQUEST/RESPONSE STRUCTURES
// ============================================================================

/// Standardized response structure for all API endpoints.
/// 
/// This structure provides a consistent response format for all API endpoints,
/// including success/error status and relevant data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiResponse<T> {
    /// Whether the request was successful
    pub success: bool,
    /// Response data (if successful)
    pub data: Option<T>,
    /// Error message (if failed)
    pub error: Option<String>,
}

/// Request structure for approval signature creation.
/// 
/// This structure contains the data needed to create an approval or rejection
/// signature for escrow operations.
#[derive(Debug, Deserialize)]
pub struct ApprovalRequest {
    /// Whether to approve (true) or reject (false) the operation
    pub approve: bool,
}

// ============================================================================
// GENERIC API HANDLERS
// ============================================================================

/// Handler for the events endpoint.
/// 
/// This function retrieves all cached events from the event monitor
/// and returns them as a JSON response.
/// 
/// # Arguments
/// 
/// * `monitor` - The event monitor instance
/// 
/// # Returns
/// 
/// * `Ok(warp::Reply)` - JSON response with cached events
/// * `Err(warp::Rejection)` - Failed to retrieve events
pub async fn get_events_handler(
    monitor: Arc<RwLock<EventMonitor>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let monitor = monitor.read().await;
    let intent_events = monitor.get_cached_events().await;
    let escrow_events = monitor.get_cached_escrow_events().await;
    let fulfillment_events = monitor.get_cached_fulfillment_events().await;
    let approvals = monitor.get_cached_approvals().await;
    
    // Return intent, escrow, fulfillment events, and approvals in a combined structure
    #[derive(Debug, Serialize)]
    struct CombinedEvents {
        intent_events: Vec<crate::monitor::RequestIntentEvent>,
        escrow_events: Vec<crate::monitor::EscrowEvent>,
        fulfillment_events: Vec<crate::monitor::FulfillmentEvent>,
        approvals: Vec<crate::monitor::EscrowApproval>,
    }
    
    let combined = CombinedEvents {
        intent_events,
        escrow_events,
        fulfillment_events,
        approvals,
    };
    
    Ok(warp::reply::json(&ApiResponse {
        success: true,
        data: Some(combined),
        error: None,
    }))
}

/// Handler for the approvals endpoint.
/// 
/// This function retrieves all cached approval signatures from the event monitor
/// and returns them as a JSON response.
/// 
/// # Arguments
/// 
/// * `monitor` - The event monitor instance
/// 
/// # Returns
/// 
/// * `Ok(warp::Reply)` - JSON response with cached approvals
/// * `Err(warp::Rejection)` - Failed to retrieve approvals
pub async fn get_approvals_handler(
    monitor: Arc<RwLock<EventMonitor>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let monitor = monitor.read().await;
    let approvals = monitor.get_cached_approvals().await;
    
    Ok(warp::reply::json(&ApiResponse {
        success: true,
        data: Some(approvals),
        error: None,
    }))
}

/// Handler for getting approval by escrow ID.
/// 
/// This function retrieves the approval signature for a specific escrow
/// and returns it as a JSON response.
/// 
/// # Arguments
/// 
/// * `escrow_id` - The escrow ID to look up
/// * `monitor` - The event monitor instance
/// 
/// # Returns
/// 
/// * `Ok(warp::Reply)` - JSON response with approval signature
/// * `Err(warp::Rejection)` - Failed to retrieve approval
pub async fn get_approval_by_escrow_handler(
    escrow_id: String,
    monitor: Arc<RwLock<EventMonitor>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let monitor = monitor.read().await;
    match monitor.get_approval_for_escrow(&escrow_id).await {
        Some(approval) => Ok(warp::reply::json(&ApiResponse {
            success: true,
            data: Some(approval),
            error: None,
        })),
        None => Ok(warp::reply::json(&ApiResponse::<crate::monitor::EscrowApproval> {
            success: false,
            data: None,
            error: Some(format!("No approval found for escrow: {}", escrow_id)),
        })),
    }
}

/// Handler for the approval endpoint.
/// 
/// This function creates an approval or rejection signature based on
/// the request parameters. It validates that escrow intents are
/// non-revocable before creating approval signatures.
/// 
/// # Arguments
/// 
/// * `request` - The approval request containing approval decision
/// * `crypto_service` - The cryptographic service instance
/// 
/// # Returns
/// 
/// * `Ok(warp::Reply)` - JSON response with approval signature
/// * `Err(warp::Rejection)` - Failed to create signature
pub async fn create_approval_handler(
    request: ApprovalRequest,
    crypto_service: Arc<RwLock<CryptoService>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let crypto_service = crypto_service.read().await;
    
    // Create the approval signature
    match crypto_service.create_approval_signature(request.approve) {
        Ok(signature) => Ok(warp::reply::json(&ApiResponse {
            success: true,
            data: Some(signature),
            error: None,
        })),
        Err(e) => Ok(warp::reply::json(&ApiResponse::<crate::crypto::ApprovalSignature> {
            success: false,
            data: None,
            error: Some(e.to_string()),
        })),
    }
}

/// Handler for the public key endpoint.
/// 
/// This function retrieves the verifier's public key for external
/// signature verification.
/// 
/// # Arguments
/// 
/// * `crypto_service` - The cryptographic service instance
/// 
/// # Returns
/// 
/// * `Ok(warp::Reply)` - JSON response with public key
/// * `Err(warp::Rejection)` - Failed to retrieve public key
pub async fn get_public_key_handler(
    crypto_service: Arc<RwLock<CryptoService>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let crypto_service = crypto_service.read().await;
    let public_key = crypto_service.get_public_key();
    
    Ok(warp::reply::json(&ApiResponse {
        success: true,
        data: Some(public_key),
        error: None,
    }))
}

// ============================================================================
// WARP FILTER HELPERS
// ============================================================================

/// Creates a warp filter that provides access to the event monitor.
/// 
/// This helper function creates a filter that injects the event monitor
/// into request handlers.
/// 
/// # Arguments
/// 
/// * `monitor` - The event monitor instance
/// 
/// # Returns
/// 
/// A warp filter that provides the monitor to handlers
pub fn with_monitor(
    monitor: Arc<RwLock<EventMonitor>>,
) -> impl Filter<Extract = (Arc<RwLock<EventMonitor>>,), Error = std::convert::Infallible> + Clone {
    warp::any().map(move || monitor.clone())
}

/// Creates a warp filter that provides access to the cryptographic service.
/// 
/// This helper function creates a filter that injects the crypto service
/// into request handlers.
/// 
/// # Arguments
/// 
/// * `crypto_service` - The cryptographic service instance
/// 
/// # Returns
/// 
/// A warp filter that provides the crypto service to handlers
pub fn with_crypto_service(
    crypto_service: Arc<RwLock<CryptoService>>,
) -> impl Filter<Extract = (Arc<RwLock<CryptoService>>,), Error = std::convert::Infallible> + Clone {
    warp::any().map(move || crypto_service.clone())
}

/// Creates a warp filter that provides access to the cross-chain validator.
/// 
/// This helper function creates a filter that injects the validator
/// into request handlers.
/// 
/// # Arguments
/// 
/// * `validator` - The cross-chain validator instance
/// 
/// # Returns
/// 
/// A warp filter that provides the validator to handlers
pub fn with_validator(
    validator: Arc<RwLock<CrossChainValidator>>,
) -> impl Filter<Extract = (Arc<RwLock<CrossChainValidator>>,), Error = std::convert::Infallible> + Clone {
    warp::any().map(move || validator.clone())
}

