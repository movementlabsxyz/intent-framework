//! REST API Server Module
//! 
//! This module provides a REST API server for the trusted verifier service,
//! exposing endpoints for monitoring events, validating fulfillments, and
//! retrieving approval signatures. It handles HTTP requests and provides
//! JSON responses for external system integration.
//! 
//! ## Security Requirements
//! 
//! **CRITICAL**: All API endpoints must validate that escrow intents are **non-revocable** 
//! (`revocable = false`) before providing any approval signatures.

use anyhow::Result;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::info;
use warp::Filter;

use crate::config::Config;
use crate::monitor::EventMonitor;
use crate::validator::CrossChainValidator;
use crate::crypto::CryptoService;

// Generic shared code
mod generic;

// Flow-specific modules (chain-agnostic)
mod inflow_generic;
mod outflow_generic;

// Flow + chain specific modules
mod inflow_aptos;
mod inflow_evm;
mod outflow_aptos;
mod outflow_evm;

// Re-export generic structures for convenience
pub use generic::ApiResponse;


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
            .and(generic::with_monitor(monitor.clone()))
            .and_then(generic::get_events_handler);
        
        // Get approvals endpoint - returns all cached approval signatures
        let approvals = warp::path("approvals")
            .and(warp::get())
            .and(generic::with_monitor(monitor.clone()))
            .and_then(generic::get_approvals_handler);
        
        // Get approval for specific escrow endpoint
        let approval_by_escrow_monitor = monitor.clone();
        let approval_by_escrow = warp::path("approvals")
            .and(warp::path::param())
            .and(warp::get())
            .and(generic::with_monitor(approval_by_escrow_monitor))
            .and_then(generic::get_approval_by_escrow_handler);
        
        // Create approval signature endpoint - creates approval/rejection signatures
        let approval = warp::path("approval")
            .and(warp::post())
            .and(warp::body::json())
            .and(generic::with_crypto_service(crypto_service.clone()))
            .and_then(generic::create_approval_handler);
        
        // Get public key endpoint - returns verifier's public key
        let public_key = warp::path("public-key")
            .and(warp::get())
            .and(generic::with_crypto_service(crypto_service.clone()))
            .and_then(generic::get_public_key_handler);
        
        // Outflow validation endpoint - validates connected chain transactions for outflow intents
        // Signature is for hub chain intent fulfillment
        let validate_outflow_monitor = monitor.clone();
        let validate_outflow_validator = _validator.clone();
        let validate_outflow_crypto = crypto_service.clone();
        let validate_outflow = warp::path("validate-outflow-fulfillment")
            .and(warp::post())
            .and(warp::body::json())
            .and(generic::with_monitor(validate_outflow_monitor))
            .and(generic::with_validator(validate_outflow_validator))
            .and(generic::with_crypto_service(validate_outflow_crypto))
            .and_then(outflow_generic::handle_outflow_fulfillment_validation);
        
        // Inflow validation endpoint - validates escrow deposits on connected chain for inflow intents
        // Signature is for connected chain escrow release (generated automatically by monitor)
        let validate_inflow_monitor = monitor.clone();
        let validate_inflow = warp::path("validate-inflow-escrow")
            .and(warp::post())
            .and(warp::body::json())
            .and(generic::with_monitor(validate_inflow_monitor))
            .and_then(inflow_generic::handle_inflow_escrow_validation);
        
        // Combine all routes
        health.or(events).or(approvals).or(approval_by_escrow).or(approval).or(public_key).or(validate_outflow).or(validate_inflow)
    }
}