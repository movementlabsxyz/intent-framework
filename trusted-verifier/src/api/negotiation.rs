//! Negotiation Routing API Module
//!
//! This module provides API endpoints for draft intent submission and retrieval,
//! enabling requesters to submit drafts and solvers to poll for pending drafts.
//! Implements polling-based, FCFS (First Come First Served) negotiation routing.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, warn};
use uuid::Uuid;
use warp::{http::StatusCode, Filter};

use crate::api::generic::ApiResponse;
use crate::config::Config;
use crate::mvm_client::MvmClient;
use crate::storage::{DraftintentStatus, DraftintentStore};

// ============================================================================
// REQUEST/RESPONSE STRUCTURES
// ============================================================================

/// Request structure for submitting a draft intent.
#[derive(Debug, Deserialize)]
pub struct DraftintentRequest {
    /// Address of the requester submitting the draft
    pub requester_address: String,
    /// Draft data (JSON object matching Draftintent structure from Move)
    pub draft_data: serde_json::Value,
    /// Expiry time (Unix timestamp)
    pub expiry_time: u64,
}

/// Response structure for draft intent submission.
#[derive(Debug, Serialize)]
pub struct DraftintentResponse {
    /// Unique identifier for the draft
    pub draft_id: String,
    /// Current status of the draft
    pub status: String,
}

/// Response structure for draft intent status.
#[derive(Debug, Serialize)]
pub struct DraftintentStatusResponse {
    /// Unique identifier for the draft
    pub draft_id: String,
    /// Current status of the draft
    pub status: String,
    /// Address of the requester
    pub requester_address: String,
    /// Timestamp when draft was created
    pub timestamp: u64,
    /// Expiry time
    pub expiry_time: u64,
}

/// Request structure for submitting a signature for a draft intent.
#[derive(Debug, Deserialize)]
pub struct SignatureSubmissionRequest {
    /// Address of the solver submitting the signature
    pub solver_address: String,
    /// Signature in hex format (Ed25519, 64 bytes)
    pub signature: String,
    /// Public key of the solver (hex format)
    pub public_key: String,
}

/// Response structure for signature submission.
#[derive(Debug, Serialize)]
pub struct SignatureSubmissionResponse {
    /// Unique identifier for the draft
    pub draft_id: String,
    /// Current status of the draft
    pub status: String,
}

/// Response structure for signature retrieval.
#[derive(Debug, Serialize)]
pub struct SignatureResponse {
    /// Signature in hex format
    pub signature: String,
    /// Address of the solver who signed (first signer)
    pub solver_address: String,
    /// Timestamp when signature was received
    pub timestamp: u64,
}

// ============================================================================
// API HANDLERS
// ============================================================================

/// Handler for POST /draftintent endpoint.
///
/// Accepts a draft intent submission from a requester.
/// Drafts are open to any solver (no solver_address required).
///
/// # Arguments
///
/// * `store` - The draft intent store
/// * `request` - The draft intent request
///
/// # Returns
///
/// * `Ok(warp::Reply)` - JSON response with draft_id and status
/// * `Err(warp::Rejection)` - Failed to create draft
pub async fn create_draftintent_handler(
    request: DraftintentRequest,
    store: Arc<RwLock<DraftintentStore>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    info!(
        "Received draft intent submission from requester: {}",
        request.requester_address
    );

    // Generate unique draft ID (UUID)
    let draft_id = Uuid::new_v4().to_string();

    // Add draft to store
    {
        let store_write = store.write().await;
        store_write
            .add_draft(
                draft_id.clone(),
                request.requester_address,
                request.draft_data,
                request.expiry_time,
            )
            .await;
    }

    info!("Created draft intent: {}", draft_id);

    Ok(warp::reply::json(&ApiResponse {
        success: true,
        data: Some(DraftintentResponse {
            draft_id,
            status: "pending".to_string(),
        }),
        error: None,
    }))
}

/// Handler for GET /draftintent/:id endpoint.
///
/// Retrieves the status of a specific draft intent.
///
/// # Arguments
///
/// * `store` - The draft intent store
/// * `draft_id` - The draft ID to retrieve
///
/// # Returns
///
/// * `Ok(warp::Reply)` - JSON response with draft status
/// * `Err(warp::Rejection)` - Draft not found (404)
pub async fn get_draftintent_handler(
    draft_id: String,
    store: Arc<RwLock<DraftintentStore>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let store_read = store.read().await;
    let draft = store_read.get_draft(&draft_id).await;
    drop(store_read);

    let draft = match draft {
        Some(d) => d,
        None => {
            return Ok(warp::reply::json(&ApiResponse::<DraftintentStatusResponse> {
                success: false,
                data: None,
                error: Some("Draft not found".to_string()),
            }));
        }
    };

    let status_str = match draft.status {
        DraftintentStatus::Pending => "pending",
        DraftintentStatus::Signed => "signed",
        DraftintentStatus::Expired => "expired",
    };

    Ok(warp::reply::json(&ApiResponse {
        success: true,
        data: Some(DraftintentStatusResponse {
            draft_id: draft.draft_id,
            status: status_str.to_string(),
            requester_address: draft.requester_address,
            timestamp: draft.timestamp,
            expiry_time: draft.expiry_time,
        }),
        error: None,
    }))
}

/// Handler for GET /draftintents/pending endpoint.
///
/// Returns all pending drafts. All solvers see all pending drafts (no filtering).
/// This is a polling endpoint - solvers call this regularly to check for new drafts.
///
/// # Arguments
///
/// * `store` - The draft intent store
///
/// # Returns
///
/// * `Ok(warp::Reply)` - JSON response with list of pending drafts
pub async fn get_pending_drafts_handler(
    store: Arc<RwLock<DraftintentStore>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let store_read = store.read().await;
    let pending_drafts = store_read.get_pending_drafts().await;
    drop(store_read);

    // Convert to response format (exclude signature data for pending drafts)
    let drafts_response: Vec<serde_json::Value> = pending_drafts
        .into_iter()
        .map(|draft| {
            serde_json::json!({
                "draft_id": draft.draft_id,
                "requester_address": draft.requester_address,
                "draft_data": draft.draft_data,
                "timestamp": draft.timestamp,
                "expiry_time": draft.expiry_time,
            })
        })
        .collect();

    Ok(warp::reply::json(&ApiResponse {
        success: true,
        data: Some(drafts_response),
        error: None,
    }))
}

/// Handler for POST /draftintent/:id/signature endpoint.
///
/// Accepts a signature submission from a solver for a draft intent.
/// Implements FCFS logic: first signature wins, later signatures are rejected with 409 Conflict.
///
/// # Arguments
///
/// * `draft_id` - The draft ID to sign
/// * `request` - The signature submission request
/// * `store` - The draft intent store
/// * `config` - Service configuration (for registry address)
///
/// # Returns
///
/// * `Ok(warp::Reply)` - JSON response with draft_id and status (200 OK for first signature, 409 Conflict for later)
/// * `Err(warp::Rejection)` - Failed to process signature
pub async fn submit_signature_handler(
    draft_id: String,
    request: SignatureSubmissionRequest,
    store: Arc<RwLock<DraftintentStore>>,
    config: Arc<Config>,
) -> Result<impl warp::Reply, warp::Rejection> {
    info!(
        "Received signature submission for draft {} from solver {}",
        draft_id, request.solver_address
    );

    // Validate solver address format: must have 0x prefix
    if !request.solver_address.starts_with("0x") {
        return Ok(warp::reply::with_status(
            warp::reply::json(&ApiResponse::<SignatureSubmissionResponse> {
                success: false,
                data: None,
                error: Some(format!(
                    "Invalid solver address '{}': must start with 0x prefix",
                    request.solver_address
                )),
            }),
            StatusCode::BAD_REQUEST,
        ));
    }
    let solver_address = request.solver_address.clone();

    // Validate solver is registered on-chain
    let registry_address = &config.hub_chain.intent_module_address;
    let hub_rpc_url = &config.hub_chain.rpc_url;

    let mvm_client = match MvmClient::new(hub_rpc_url) {
        Ok(client) => client,
        Err(e) => {
            warn!("Failed to create MvmClient: {}", e);
            return Ok(warp::reply::with_status(
                warp::reply::json(&ApiResponse::<SignatureSubmissionResponse> {
                    success: false,
                    data: None,
                    error: Some("Failed to connect to hub chain".to_string()),
                }),
                StatusCode::INTERNAL_SERVER_ERROR,
            ));
        }
    };

    // Check if solver is registered
    let solver_registered = match mvm_client
        .get_solver_public_key(&solver_address, registry_address)
        .await
    {
        Ok(Some(_)) => true,
        Ok(None) => false,
        Err(e) => {
            warn!("Failed to query solver registry: {}", e);
            return Ok(warp::reply::with_status(
                warp::reply::json(&ApiResponse::<SignatureSubmissionResponse> {
                    success: false,
                    data: None,
                    error: Some(format!("Failed to verify solver registration: {}", e)),
                }),
                StatusCode::INTERNAL_SERVER_ERROR,
            ));
        }
    };

    if !solver_registered {
        return Ok(warp::reply::with_status(
            warp::reply::json(&ApiResponse::<SignatureSubmissionResponse> {
                success: false,
                data: None,
                error: Some(format!(
                    "Solver {} is not registered on-chain",
                    solver_address
                )),
            }),
            StatusCode::BAD_REQUEST,
        ));
    }

    // Validate signature format
    if let Err(e) = validate_signature_format(&request.signature) {
        return Ok(warp::reply::with_status(
            warp::reply::json(&ApiResponse::<SignatureSubmissionResponse> {
                success: false,
                data: None,
                error: Some(e),
            }),
            StatusCode::BAD_REQUEST,
        ));
    }

    // Add signature to store (FCFS logic handled in add_signature)
    let store_write = store.write().await;
    let result = store_write
        .add_signature(
            &draft_id,
            solver_address.clone(),
            request.signature.clone(),
            request.public_key.clone(),
        )
        .await;

    drop(store_write);

    match result {
        Ok(()) => {
            info!("Successfully added signature for draft {}", draft_id);
            Ok(warp::reply::with_status(
                warp::reply::json(&ApiResponse {
                    success: true,
                    data: Some(SignatureSubmissionResponse {
                        draft_id,
                        status: "signed".to_string(),
                    }),
                    error: None,
                }),
                StatusCode::OK,
            ))
        }
        Err(e) => {
            // Check if it's an FCFS conflict (already signed)
            if e.contains("already signed") {
                warn!("Draft {} already signed - rejecting duplicate signature", draft_id);
                Ok(warp::reply::with_status(
                    warp::reply::json(&ApiResponse::<SignatureSubmissionResponse> {
                        success: false,
                        data: None,
                        error: Some("Draft already signed by another solver".to_string()),
                    }),
                    StatusCode::CONFLICT, // 409 Conflict
                ))
            } else {
                warn!("Failed to add signature for draft {}: {}", draft_id, e);
                Ok(warp::reply::with_status(
                    warp::reply::json(&ApiResponse::<SignatureSubmissionResponse> {
                        success: false,
                        data: None,
                        error: Some(e),
                    }),
                    StatusCode::BAD_REQUEST,
                ))
            }
        }
    }
}

/// Handler for GET /draftintent/:id/signature endpoint.
///
/// Retrieves the signature for a draft intent (first signature received).
/// This is a polling endpoint - requesters call this regularly to check if signature is available.
///
/// # Arguments
///
/// * `draft_id` - The draft ID to retrieve signature for
/// * `store` - The draft intent store
///
/// # Returns
///
/// * `Ok(warp::Reply)` - JSON response with signature (200 OK if signed, 202 Accepted if pending)
/// * `Err(warp::Rejection)` - Draft not found (404)
pub async fn get_signature_handler(
    draft_id: String,
    store: Arc<RwLock<DraftintentStore>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let store_read = store.read().await;
    let draft = store_read.get_draft(&draft_id).await;
    drop(store_read);

    let draft = match draft {
        Some(d) => d,
        None => {
            return Ok(warp::reply::with_status(
                warp::reply::json(&ApiResponse::<SignatureResponse> {
                    success: false,
                    data: None,
                    error: Some("Draft not found".to_string()),
                }),
                StatusCode::NOT_FOUND,
            ));
        }
    };

    match draft.signature {
        Some(sig) => {
            // Draft is signed - return signature
            Ok(warp::reply::with_status(
                warp::reply::json(&ApiResponse {
                    success: true,
                    data: Some(SignatureResponse {
                        signature: sig.signature,
                        solver_address: sig.solver_address,
                        timestamp: sig.signature_timestamp,
                    }),
                    error: None,
                }),
                StatusCode::OK,
            ))
        }
        None => {
            // Draft not yet signed - return 202 Accepted
            Ok(warp::reply::with_status(
                warp::reply::json(&ApiResponse::<SignatureResponse> {
                    success: false,
                    data: None,
                    error: Some("Draft not yet signed".to_string()),
                }),
                StatusCode::ACCEPTED, // 202 Accepted
            ))
        }
    }
}

// ============================================================================
// VALIDATION HELPERS
// ============================================================================

/// Validates Ed25519 signature format.
///
/// Checks that the signature is:
/// - 128 hex characters (64 bytes) after removing optional 0x prefix
/// - Valid hex characters only
///
/// # Arguments
///
/// * `signature` - Signature string (with or without 0x prefix)
///
/// # Returns
///
/// * `Ok(())` if signature format is valid
/// * `Err(String)` with error message if invalid
pub fn validate_signature_format(signature: &str) -> Result<(), String> {
    let signature_hex = signature.strip_prefix("0x").unwrap_or(signature);
    
    // Check length (Ed25519 signature is 64 bytes = 128 hex chars)
    if signature_hex.len() != 128 {
        return Err(format!(
            "Invalid signature format: expected 128 hex characters (64 bytes), got {}",
            signature_hex.len()
        ));
    }
    
    // Check hex format
    if !signature_hex.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("Invalid signature format: not valid hex".to_string());
    }
    
    Ok(())
}

// ============================================================================
// WARP FILTER HELPERS
// ============================================================================

/// Helper function to inject DraftintentStore into handlers.
pub fn with_draft_store(
    store: Arc<RwLock<DraftintentStore>>,
) -> impl Filter<Extract = (Arc<RwLock<DraftintentStore>>,), Error = std::convert::Infallible> + Clone
{
    warp::any().map(move || store.clone())
}
