//! Trusted Verifier Service
//! 
//! A trusted verifier service that monitors escrow deposit events and triggers actions 
//! on other chains or systems. This service provides cross-chain validation and 
//! cryptographic approval signatures for escrow completion.
//! 
//! ## Overview
//! 
//! The trusted verifier is an external service that:
//! 1. Monitors intent events on the hub chain for new intents
//! 2. Monitors escrow events from escrow systems
//! 3. Validates fulfillment of intent (deposit conditions) on the connected chain
//! 4. Provides approval/rejection confirmation for intent fulfillment
//! 5. Provides approval/rejection for escrow completion
//! 
//! ## Security Requirements
//! 
//! ⚠️ **CRITICAL**: The verifier must ensure that escrow intents are **non-revocable** 
//! (`revocable = false`) before triggering any actions elsewhere.

use anyhow::Result;
use tracing::info;

mod monitor;
mod validator;
mod crypto;
mod config;
mod api;
mod aptos_client;
mod evm_client;

use config::Config;

// ============================================================================
// MAIN APPLICATION ENTRY POINT
// ============================================================================

/// Main application entry point that initializes and runs the trusted verifier service.
/// 
/// This function:
/// 1. Initializes logging and tracing
/// 2. Loads configuration from TOML file
/// 3. Initializes all service components (monitor, validator, crypto)
/// 4. Starts the API server
/// 5. Runs the service until shutdown
#[tokio::main]
async fn main() -> Result<()> {
    // Initialize structured logging for debugging and monitoring
    tracing_subscriber::fmt::init();
    
    info!("Starting Trusted Verifier Service");
    
    // Load configuration from config/verifier.toml
    let config = Config::load()?;
    info!("Configuration loaded successfully");
    
    // Initialize all service components
    let monitor = monitor::EventMonitor::new(&config).await?;
    let validator = validator::CrossChainValidator::new(&config).await?;
    let crypto_service = crypto::CryptoService::new(&config)?;
    
    info!("All components initialized successfully");
    
    // Start the REST API server
    let api_server = api::ApiServer::new(config.clone(), monitor.clone(), validator, crypto_service);
    
    // Start background monitoring
    info!("Starting background event monitoring");
    let monitor_for_background = monitor.clone();
    tokio::spawn(async move {
        if let Err(e) = monitor_for_background.start_monitoring().await {
            eprintln!("Monitoring error: {}", e);
        }
    });
    
    // Run the service (this blocks until shutdown)
    api_server.run().await?;
    
    Ok(())
}