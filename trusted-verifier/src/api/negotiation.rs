//! Negotiation Routing API Module
//!
//! This module provides API endpoints for draft intent submission and retrieval,
//! enabling requesters to submit drafts and solvers to poll for pending drafts.
//! Implements polling-based, FCFS (First Come First Served) negotiation routing.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::info;
use uuid::Uuid;
use warp::Filter;

use crate::api::generic::ApiResponse;
use crate::storage::{DraftIntentStatus, DraftIntentStore};

// ============================================================================
// REQUEST/RESPONSE STRUCTURES
// ============================================================================

/// Request structure for submitting a draft intent.
#[derive(Debug, Deserialize)]
pub struct DraftIntentRequest {
    /// Address of the requester submitting the draft
    pub requester_address: String,
    /// Draft data (JSON object matching IntentDraft structure from Move)
    pub draft_data: serde_json::Value,
    /// Expiry time (Unix timestamp)
    pub expiry_time: u64,
}

/// Response structure for draft intent submission.
#[derive(Debug, Serialize)]
pub struct DraftIntentResponse {
    /// Unique identifier for the draft
    pub draft_id: String,
    /// Current status of the draft
    pub status: String,
}

/// Response structure for draft intent status.
#[derive(Debug, Serialize)]
pub struct DraftIntentStatusResponse {
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

// ============================================================================
// API HANDLERS
// ============================================================================

/// Handler for POST /draft-intent endpoint.
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
pub async fn create_draft_intent_handler(
    request: DraftIntentRequest,
    store: Arc<RwLock<DraftIntentStore>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    info!(
        "Received draft intent submission from requester: {}",
        request.requester_address
    );

    // Generate unique draft ID (UUID)
    let draft_id = Uuid::new_v4().to_string();

    // Add draft to store
    {
        let store_read = store.read().await;
        store_read
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
        data: Some(DraftIntentResponse {
            draft_id,
            status: "pending".to_string(),
        }),
        error: None,
    }))
}

/// Handler for GET /draft-intent/:id endpoint.
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
pub async fn get_draft_intent_handler(
    draft_id: String,
    store: Arc<RwLock<DraftIntentStore>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let store_read = store.read().await;
    let draft = store_read.get_draft(&draft_id).await;
    drop(store_read);

    let draft = match draft {
        Some(d) => d,
        None => {
            return Ok(warp::reply::json(&ApiResponse::<DraftIntentStatusResponse> {
                success: false,
                data: None,
                error: Some("Draft not found".to_string()),
            }));
        }
    };

    let status_str = match draft.status {
        DraftIntentStatus::Pending => "pending",
        DraftIntentStatus::Signed => "signed",
        DraftIntentStatus::Expired => "expired",
    };

    Ok(warp::reply::json(&ApiResponse {
        success: true,
        data: Some(DraftIntentStatusResponse {
            draft_id: draft.draft_id,
            status: status_str.to_string(),
            requester_address: draft.requester_address,
            timestamp: draft.timestamp,
            expiry_time: draft.expiry_time,
        }),
        error: None,
    }))
}

/// Handler for GET /draft-intents/pending endpoint.
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
    store: Arc<RwLock<DraftIntentStore>>,
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

// ============================================================================
// WARP FILTER HELPERS
// ============================================================================

/// Helper function to inject DraftIntentStore into handlers.
pub fn with_draft_store(
    store: Arc<RwLock<DraftIntentStore>>,
) -> impl Filter<Extract = (Arc<RwLock<DraftIntentStore>>,), Error = std::convert::Infallible> + Clone
{
    warp::any().map(move || store.clone())
}

