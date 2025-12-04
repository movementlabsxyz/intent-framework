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

use anyhow::Result;
use clap::Parser;
use solver::{
    config::SolverConfig,
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
        std::env::set_var("SOLVER_CONFIG_PATH", &path);
        SolverConfig::load()?
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

