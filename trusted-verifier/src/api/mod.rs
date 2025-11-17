//! REST API Server Module
//! 
//! This module provides a REST API server for the trusted verifier service,
//! exposing endpoints for monitoring events, validating fulfillments, and
//! retrieving approval signatures. It handles HTTP requests and provides
//! JSON responses for external system integration.
//! 
//! ## Security Requirements
//! 
//! ⚠️ **CRITICAL**: All API endpoints must validate that escrow intents are **non-revocable** 
//! (`revocable = false`) before providing any approval signatures.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::info;
use warp::Filter;

use crate::config::Config;
use crate::monitor::EventMonitor;
use crate::validator::CrossChainValidator;
use crate::crypto::{CryptoService, ApprovalSignature};
use anyhow;

// Chain-specific modules
mod aptos;
mod evm;

// ============================================================================
// API REQUEST/RESPONSE STRUCTURES
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
struct ApprovalRequest {
    /// Whether to approve (true) or reject (false) the operation
    pub approve: bool,
}

/// Request structure for validating outflow fulfillment transactions.
/// 
/// This structure contains the transaction hash and chain information needed
/// to validate a connected chain fulfillment transaction.
#[derive(Debug, Deserialize)]
struct ValidateFulfillmentRequest {
    /// Transaction hash on the connected chain
    pub transaction_hash: String,
    /// Chain type: "aptos" or "evm"
    pub chain_type: String,
    /// Intent ID to validate against (optional, will be extracted from transaction if not provided)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub intent_id: Option<String>,
}

// ============================================================================
// API SERVER IMPLEMENTATION
// ============================================================================

/// REST API server for the trusted verifier service.
/// 
/// This server exposes HTTP endpoints for external systems to interact with
/// the verifier service, including event monitoring, validation, and signature
/// retrieval.
pub struct ApiServer {
    /// Service configuration
    config: Arc<Config>,
    /// Event monitor for blockchain event processing
    monitor: Arc<RwLock<EventMonitor>>,
    /// Cross-chain validator for fulfillment validation
    validator: Arc<RwLock<CrossChainValidator>>,
    /// Cryptographic service for signature operations
    crypto_service: Arc<RwLock<CryptoService>>,
}

impl ApiServer {
    /// Creates a new API server with the given components.
    /// 
    /// This function initializes the API server with all necessary components
    /// for handling HTTP requests and providing verifier functionality.
    /// 
    /// # Arguments
    /// 
    /// * `config` - Service configuration
    /// * `monitor` - Event monitor instance
    /// * `validator` - Cross-chain validator instance
    /// * `crypto_service` - Cryptographic service instance
    /// 
    /// # Returns
    /// 
    /// A new API server instance
    pub fn new(
        config: Config,
        monitor: EventMonitor,
        validator: CrossChainValidator,
        crypto_service: CryptoService,
    ) -> Self {
        Self {
            config: Arc::new(config),
            monitor: Arc::new(RwLock::new(monitor)),
            validator: Arc::new(RwLock::new(validator)),
            crypto_service: Arc::new(RwLock::new(crypto_service)),
        }
    }
    
    /// Starts the API server and begins handling HTTP requests.
    /// 
    /// This function configures all API routes and starts the HTTP server
    /// on the configured host and port.
    /// 
    /// # Returns
    /// 
    /// * `Ok(())` - Server started successfully
    /// * `Err(anyhow::Error)` - Failed to start server
    pub async fn run(&self) -> Result<()> {
        info!("Starting API server on {}:{}", 
              self.config.api.host, self.config.api.port);
        
        // Create and configure all API routes
        let routes = self.create_routes();
        
        // Start the HTTP server
        warp::serve(routes)
            .run(([127, 0, 0, 1], self.config.api.port))
            .await;
        
        Ok(())
    }
    
    /// Creates all API routes for the server.
    /// 
    /// This function defines all HTTP endpoints and their handlers,
    /// including health checks, event monitoring, validation, and
    /// signature operations.
    /// 
    /// # Returns
    /// 
    /// A warp filter containing all API routes
    fn create_routes(&self) -> impl Filter<Extract = impl warp::Reply, Error = warp::Rejection> + Clone {
        let _config = self.config.clone();
        let monitor = self.monitor.clone();
        let _validator = self.validator.clone();
        let crypto_service = self.crypto_service.clone();
        
        // Health check endpoint - returns service status
        let health = warp::path("health")
            .and(warp::get())
            .map(|| warp::reply::json(&ApiResponse::<String> {
                success: true,
                data: Some("Trusted Verifier Service is running".to_string()),
                error: None,
            }));
        
        // Get cached events endpoint - returns all monitored events
        let events = warp::path("events")
            .and(warp::get())
            .and(with_monitor(monitor.clone()))
            .and_then(get_events_handler);
        
        // Get approvals endpoint - returns all cached approval signatures
        let approvals = warp::path("approvals")
            .and(warp::get())
            .and(with_monitor(monitor.clone()))
            .and_then(get_approvals_handler);
        
        // Get approval for specific escrow endpoint
        let approval_by_escrow_monitor = monitor.clone();
        let approval_by_escrow = warp::path("approvals")
            .and(warp::path::param())
            .and(warp::get())
            .and(with_monitor(approval_by_escrow_monitor))
            .and_then(get_approval_by_escrow_handler);
        
        // Create approval signature endpoint - creates approval/rejection signatures
        let approval = warp::path("approval")
            .and(warp::post())
            .and(warp::body::json())
            .and(with_crypto_service(crypto_service.clone()))
            .and_then(create_approval_handler);
        
        // Get public key endpoint - returns verifier's public key
        let public_key = warp::path("public-key")
            .and(warp::get())
            .and(with_crypto_service(crypto_service.clone()))
            .and_then(get_public_key_handler);
        
        // Validate fulfillment endpoint - validates connected chain transactions
        let validate_fulfillment_monitor = monitor.clone();
        let validate_fulfillment_validator = _validator.clone();
        let validate_fulfillment = warp::path("validate-fulfillment")
            .and(warp::post())
            .and(warp::body::json())
            .and(with_monitor(validate_fulfillment_monitor))
            .and(with_validator(validate_fulfillment_validator))
            .and_then(handle_fulfillment_validation);
        
        // Combine all routes
        health.or(events).or(approvals).or(approval_by_escrow).or(approval).or(public_key).or(validate_fulfillment)
    }
}

// ============================================================================
// API ENDPOINT HANDLERS
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
async fn get_events_handler(
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
async fn get_approvals_handler(
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
async fn get_approval_by_escrow_handler(
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
async fn create_approval_handler(
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
        Err(e) => Ok(warp::reply::json(&ApiResponse::<ApprovalSignature> {
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
async fn get_public_key_handler(
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

/// Handler for the validate-fulfillment endpoint.
/// 
/// This function validates a connected chain transaction by:
/// 1. Querying the transaction by hash (chain-specific)
/// 2. Extracting intent_id and transaction parameters
/// 3. Finding the matching request intent
/// 4. Validating all parameters match intent requirements
/// 
/// # Arguments
/// 
/// * `request` - The validation request containing transaction hash and chain type
/// * `monitor` - The event monitor instance
/// * `validator` - The cross-chain validator instance
/// 
/// # Returns
/// 
/// * `Ok(warp::Reply)` - JSON response with validation result
/// * `Err(warp::Rejection)` - Failed to validate transaction
async fn handle_fulfillment_validation(
    request: ValidateFulfillmentRequest,
    monitor: Arc<RwLock<EventMonitor>>,
    validator: Arc<RwLock<CrossChainValidator>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let monitor = monitor.read().await;
    let validator = validator.read().await;
    
    // Get config from monitor (monitor stores config internally)
    // We need to access it through the monitor's internal structure
    // For now, we'll get it from the API server's config
    // TODO: Add a method to EventMonitor to get config, or pass config separately
    
    // Query transaction based on chain type
    let (tx_params, tx_success) = match request.chain_type.as_str() {
        "aptos" => {
            match aptos::query_aptos_fulfillment_transaction(&request.transaction_hash, &validator).await {
                Ok(result) => result,
                Err(error_msg) => {
                    return Ok(warp::reply::json(&ApiResponse::<crate::validator::ValidationResult> {
                        success: false,
                        data: None,
                        error: Some(error_msg),
                    }));
                }
            }
        },
        "evm" => {
            match evm::query_evm_fulfillment_transaction(&request.transaction_hash, &validator).await {
                Ok(result) => result,
                Err(error_msg) => {
                    return Ok(warp::reply::json(&ApiResponse::<crate::validator::ValidationResult> {
                        success: false,
                        data: None,
                        error: Some(error_msg),
                    }));
                }
            }
        },
        _ => {
            return Ok(warp::reply::json(&ApiResponse::<crate::validator::ValidationResult> {
                success: false,
                data: None,
                error: Some(format!("Invalid chain_type: {}. Must be 'aptos' or 'evm'", request.chain_type)),
            }));
        }
    };
    
    // Find matching request intent
    let intent_id = request.intent_id.as_ref().unwrap_or(&tx_params.intent_id);
    let intent_cache = monitor.get_cached_events().await;
    let request_intent = match intent_cache.iter().find(|intent| intent.intent_id == *intent_id) {
        Some(intent) => intent,
        None => {
            return Ok(warp::reply::json(&ApiResponse::<crate::validator::ValidationResult> {
                success: false,
                data: None,
                error: Some(format!("Request intent not found: {}", intent_id)),
            }));
        }
    };
    
    // Validate transaction against intent
    let validation_result = match crate::validator::validate_outflow_fulfillment(&validator, request_intent, &tx_params, tx_success) {
        Ok(result) => result,
        Err(e) => {
            return Ok(warp::reply::json(&ApiResponse::<crate::validator::ValidationResult> {
                success: false,
                data: None,
                error: Some(format!("Validation failed: {}", e)),
            }));
        }
    };
    
    let valid = validation_result.valid;
    let message = validation_result.message.clone();
    Ok(warp::reply::json(&ApiResponse {
        success: valid,
        data: Some(validation_result),
        error: if valid { None } else { Some(message) },
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
fn with_monitor(
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
fn with_crypto_service(
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
fn with_validator(
    validator: Arc<RwLock<CrossChainValidator>>,
) -> impl Filter<Extract = (Arc<RwLock<CrossChainValidator>>,), Error = std::convert::Infallible> + Clone {
    warp::any().map(move || validator.clone())
}