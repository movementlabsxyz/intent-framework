//! Outflow validation API handlers (chain-agnostic)
//!
//! This module handles API endpoints for outflow intent validation.
//! Outflow intents have tokens locked on the hub chain and request tokens on the connected chain.
//!
//! The validation flow:
//! 1. Solver transfers tokens to requester on connected chain
//! 2. Solver submits transaction hash to verifier via API
//! 3. Verifier validates transaction matches intent requirements
//! 4. Verifier generates approval signature for hub chain intent fulfillment
//! 5. Solver uses signature to fulfill hub intent via finish_fa_receiving_session_with_oracle()

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{error, info};

use crate::api::generic::ApiResponse;
use crate::crypto::ApprovalSignature;
use crate::monitor::EventMonitor;
use crate::validator::CrossChainValidator;

// Chain-specific modules
use super::outflow_evm;
use super::outflow_mvm;

// ============================================================================
// REQUEST/RESPONSE STRUCTURES
// ============================================================================

/// Request structure for validating outflow fulfillment transactions.
///
/// This structure contains the transaction hash and chain information needed
/// to validate a connected chain fulfillment transaction for an outflow intent.
#[derive(Debug, Deserialize)]
pub struct ValidateOutflowFulfillmentRequest {
    /// Transaction hash on the connected chain
    pub transaction_hash: String,
    /// Chain type: "mvm" or "evm"
    pub chain_type: String,
    /// Intent ID to validate against (optional, will be extracted from transaction if not provided)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub intent_id: Option<String>,
}

/// Response structure for outflow fulfillment validation that includes both validation result and approval signature.
///
/// The approval signature is for fulfilling the hub chain intent via finish_fa_receiving_session_with_oracle().
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutflowFulfillmentValidationResponse {
    /// Validation result
    pub validation: crate::validator::ValidationResult,
    /// Approval signature for hub chain intent fulfillment (only present if validation passed)
    /// This signature is used by the solver to fulfill the hub intent via oracle-guarded intent mechanism
    pub approval_signature: Option<ApprovalSignature>,
}

// ============================================================================
// API HANDLERS
// ============================================================================

/// Handler for the validate-outflow-fulfillment endpoint.
///
/// This function validates a connected chain transaction for an outflow intent by:
/// 1. Querying the transaction by hash (chain-specific)
/// 2. Extracting intent_id and transaction parameters
/// 3. Finding the matching request intent
/// 4. Validating all parameters match intent requirements
/// 5. Generating approval signature for hub chain fulfillment if validation passes
///
/// The approval signature is used by the solver to fulfill the hub intent via
/// finish_fa_receiving_session_with_oracle() on the hub chain.
///
/// # Arguments
///
/// * `request` - The validation request containing transaction hash and chain type
/// * `monitor` - The event monitor instance
/// * `validator` - The cross-chain validator instance
/// * `crypto_service` - The cryptographic service instance for signature generation
///
/// # Returns
///
/// * `Ok(warp::Reply)` - JSON response with validation result and approval signature (if valid)
/// * `Err(warp::Rejection)` - Failed to validate transaction
pub async fn handle_outflow_fulfillment_validation(
    request: ValidateOutflowFulfillmentRequest,
    monitor: Arc<RwLock<EventMonitor>>,
    validator: Arc<RwLock<CrossChainValidator>>,
    crypto_service: Arc<RwLock<crate::crypto::CryptoService>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let monitor = monitor.read().await;
    let validator = validator.read().await;

    // Query transaction based on chain type (chain-specific)
    let (tx_params, tx_success) = match request.chain_type.as_str() {
        "mvm" => {
            match outflow_mvm::query_mvm_fulfillment_transaction(
                &request.transaction_hash,
                &validator,
            )
            .await
            {
                Ok(result) => result,
                Err(error_msg) => {
                    return Ok(warp::reply::json(&ApiResponse::<
                        OutflowFulfillmentValidationResponse,
                    > {
                        success: false,
                        data: None,
                        error: Some(error_msg),
                    }));
                }
            }
        }
        "evm" => {
            match outflow_evm::query_evm_fulfillment_transaction(
                &request.transaction_hash,
                &validator,
            )
            .await
            {
                Ok(result) => result,
                Err(error_msg) => {
                    return Ok(warp::reply::json(&ApiResponse::<
                        OutflowFulfillmentValidationResponse,
                    > {
                        success: false,
                        data: None,
                        error: Some(error_msg),
                    }));
                }
            }
        }
        _ => {
            return Ok(warp::reply::json(&ApiResponse::<
                OutflowFulfillmentValidationResponse,
            > {
                success: false,
                data: None,
                error: Some(format!(
                    "Invalid chain_type: {}. Must be 'mvm' or 'evm'",
                    request.chain_type
                )),
            }));
        }
    };

    // Find matching request intent (flow-agnostic logic)
    let intent_id = request.intent_id.as_ref().unwrap_or(&tx_params.intent_id);
    let intent_cache = monitor.get_cached_events().await;
    let request_intent = match intent_cache
        .iter()
        .find(|intent| intent.intent_id == *intent_id)
    {
        Some(intent) => intent,
        None => {
            return Ok(warp::reply::json(&ApiResponse::<
                OutflowFulfillmentValidationResponse,
            > {
                success: false,
                data: None,
                error: Some(format!("Request intent not found: {}", intent_id)),
            }));
        }
    };

    // Validate transaction against intent (flow-agnostic logic)
    let validation_result = match crate::validator::validate_outflow_fulfillment(
        &validator,
        request_intent,
        &tx_params,
        tx_success,
    )
    .await
    {
        Ok(result) => result,
        Err(e) => {
            return Ok(warp::reply::json(&ApiResponse::<
                OutflowFulfillmentValidationResponse,
            > {
                success: false,
                data: None,
                error: Some(format!("Validation failed: {}", e)),
            }));
        }
    };

    // If validation passed, generate approval signature for hub chain fulfillment
    // Note: Hub chain is always Move VM, so we always use Ed25519 signature
    let approval_signature = if validation_result.valid {
        let crypto = crypto_service.read().await;
        let intent_id = intent_id.clone();

        // Generate signature for hub chain (always Move VM/Ed25519 regardless of connected chain type)
        match crypto.create_mvm_approval_signature(&intent_id) {
            Ok(sig) => {
                info!("Generated hub chain approval signature for outflow intent_id: {} (signature for hub chain fulfillment)", intent_id);
                Some(sig)
            }
            Err(e) => {
                error!("Failed to generate hub chain approval signature: {}", e);
                return Ok(warp::reply::json(&ApiResponse::<
                    OutflowFulfillmentValidationResponse,
                > {
                    success: false,
                    data: None,
                    error: Some(format!("Failed to generate approval signature: {}", e)),
                }));
            }
        }
    } else {
        None
    };

    let response = OutflowFulfillmentValidationResponse {
        validation: validation_result,
        approval_signature,
    };

    Ok(warp::reply::json(&ApiResponse {
        success: true,
        data: Some(response),
        error: None,
    }))
}
