//! Solver Service
//!
//! Main service binary that runs all solver services concurrently:
//! - Signing service: polls verifier and signs accepted drafts
//! - Intent tracker: monitors hub chain for intent creation
//! - Inflow service: monitors escrows and fulfills inflow intents
//! - Outflow service: executes transfers and fulfills outflow intents
//!
//! ## Usage
//!
//! ```bash
//! cargo run --bin solver -- --config solver.toml
//! ```
//!
//! Or set the config path via environment variable:
//!
//! ```bash
//! SOLVER_CONFIG_PATH=solver.toml cargo run --bin solver
//! ```

use anyhow::{Context, Result};
use clap::Parser;
use solver::{
    chains::HubChainClient,
    config::SolverConfig,
    crypto::{get_private_key_from_profile, sign_intent_hash},
    service::{InflowService, IntentTracker, OutflowService, SigningService},
};
use std::sync::Arc;
use std::time::Duration;
use tokio::signal;
use tracing::{error, info};

#[derive(Parser, Debug)]
#[command(name = "solver")]
#[command(about = "Solver service for intent framework - signs and fulfills intents")]
struct Args {
    /// Path to solver configuration file (default: solver.toml or SOLVER_CONFIG_PATH env var)
    #[arg(short, long)]
    config: Option<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Parse command line arguments first (before initializing logging)
    let args = Args::parse();

    // Initialize structured logging
    tracing_subscriber::fmt::init();

    info!("Starting Solver Service");

    // Load configuration
    // Priority: CLI arg > env var > default
    let config = if let Some(path) = args.config {
        info!("Loading configuration from: {}", path);
        SolverConfig::load_from_path(Some(&path))?
    } else {
        // Check if SOLVER_CONFIG_PATH is set
        if let Ok(path) = std::env::var("SOLVER_CONFIG_PATH") {
            info!("Loading configuration from SOLVER_CONFIG_PATH: {}", path);
        } else {
            info!("Loading configuration from default location");
        }
        SolverConfig::load()?
    };

    info!("Configuration loaded successfully");
    info!("Verifier URL: {}", config.service.verifier_url);
    info!("Polling interval: {}ms", config.service.polling_interval_ms);
    info!("Hub chain: {} (chain ID: {})", config.hub_chain.name, config.hub_chain.chain_id);
    info!("Solver address: {}", config.solver.address);

    // Check if solver is registered on-chain, and register if not
    info!("Checking solver registration on hub chain...");
    let hub_client = HubChainClient::new(&config.hub_chain)?;
    match hub_client.is_solver_registered(&config.solver.address).await {
        Ok(true) => {
            info!("✅ Solver is registered on-chain");
        }
        Ok(false) => {
            info!("Solver is not registered. Registering on-chain...");
            
            // Get solver's private key - try environment variable first, then profile
            let private_key = if let Ok(key_str) = std::env::var("MOVEMENT_SOLVER_PRIVATE_KEY") {
                // Read from environment variable (hex format)
                let key_hex = key_str.strip_prefix("0x").unwrap_or(&key_str);
                let key_bytes = hex::decode(key_hex)
                    .context("Failed to decode MOVEMENT_SOLVER_PRIVATE_KEY from hex")?;
                if key_bytes.len() != 32 {
                    anyhow::bail!("MOVEMENT_SOLVER_PRIVATE_KEY must be 32 bytes (64 hex chars)");
                }
                let mut key_array = [0u8; 32];
                key_array.copy_from_slice(&key_bytes);
                key_array
            } else {
                // Fall back to reading from profile
                get_private_key_from_profile(&config.solver.profile)
                    .context("Failed to get private key from profile or MOVEMENT_SOLVER_PRIVATE_KEY env var")?
            };
            
            // Derive public key from private key (we can use a dummy hash since we only need the public key)
            let dummy_hash = [0u8; 32];
            let (_signature, public_key_bytes) = sign_intent_hash(&dummy_hash, &private_key)
                .context("Failed to derive public key from private key")?;
            
            // Get EVM address and MVM address from environment variables
            // These are set by sourcing the keys file (e.g., .testnet-keys.env or .e2e-tests-keys.env)
            let (evm_address, mvm_address): (Vec<u8>, Option<String>) = match &config.connected_chain {
                solver::config::ConnectedChainConfig::Evm(_) => {
                    // For EVM connected chains, read solver's EVM address from env var
                    let evm_addr = std::env::var("SOLVER_EVM_ADDRESS")
                        .or_else(|_| std::env::var("BASE_SOLVER_ADDRESS")) // fallback for testnet
                        .ok()
                        .and_then(|addr| {
                            let addr = addr.strip_prefix("0x").unwrap_or(&addr);
                            hex::decode(addr).ok()
                        })
                        .unwrap_or_default();
                    (evm_addr, None)
                }
                solver::config::ConnectedChainConfig::Mvm(_) => {
                    // For MVM connected chains, read solver's MVM address from env var
                    let mvm_addr = std::env::var("SOLVER_CONNECTED_MVM_ADDRESS").ok();
                    (vec![], mvm_addr)
                }
            };
            
            // Register the solver
            // Pass private key if we have it from env var (testnet mode), otherwise use profile (E2E mode)
            let pk_for_registration = if std::env::var("MOVEMENT_SOLVER_PRIVATE_KEY").is_ok() {
                Some(&private_key)
            } else {
                None
            };
            match hub_client.register_solver(&public_key_bytes, &evm_address, mvm_address.as_deref(), pk_for_registration) {
                Ok(tx_hash) => {
                    info!("✅ Solver registered successfully. Transaction: {}", tx_hash);
                }
                Err(e) => {
                    // If registration fails (e.g., already registered by another process),
                    // check again to see if we're now registered
                    match hub_client.is_solver_registered(&config.solver.address).await {
                        Ok(true) => {
                            info!("✅ Solver is now registered (may have been registered by another process)");
                        }
                        _ => {
                            anyhow::bail!("Failed to register solver: {}", e);
                        }
                    }
                }
            }
        }
        Err(e) => {
            anyhow::bail!(
                "Failed to check solver registration: {}\n\
                This may indicate:\n\
                - RPC endpoint is unreachable\n\
                - Module address is incorrect\n\
                - View function is not available (module may need to be redeployed with #[view] attribute)\n\
                - Network connectivity issues",
                e
            );
        }
    }

    // Create shared intent tracker
    let tracker = Arc::new(IntentTracker::new(&config)?);
    info!("Intent tracker initialized");

    // Create services
    let signing_service = SigningService::new(config.clone(), tracker.clone())?;
    info!("Signing service initialized");

    let inflow_service = InflowService::new(config.clone(), tracker.clone())?;
    info!("Inflow service initialized");

    let outflow_service = OutflowService::new(config.clone(), tracker.clone())?;
    info!("Outflow service initialized");

    let polling_interval = Duration::from_millis(config.service.polling_interval_ms);

    // Run all services concurrently with graceful shutdown
    info!("Starting all services...");
    
    tokio::select! {
        // Signing service loop
        result = signing_service.run() => {
            if let Err(e) = result {
                error!("Signing service error: {}", e);
            }
        }
        
        // Intent tracker loop (polls hub chain for created intents)
        _ = async {
            loop {
                if let Err(e) = tracker.poll_for_created_intents().await {
                    error!("Intent tracker error: {}", e);
                }
                tokio::time::sleep(polling_interval).await;
            }
        } => {}
        
        // Inflow fulfillment service loop
        result = inflow_service.run() => {
            if let Err(e) = result {
                error!("Inflow service error: {}", e);
            }
        }
        
        // Outflow fulfillment service loop
        _ = outflow_service.run(polling_interval) => {}
        
        // Graceful shutdown on Ctrl+C
        _ = signal::ctrl_c() => {
            info!("Received shutdown signal, stopping services...");
        }
    }

    info!("Solver service stopped");
    Ok(())
}

