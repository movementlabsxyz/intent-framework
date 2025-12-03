//! Solver Service
//!
//! Main service binary that runs the solver signing loop.
//! Polls the verifier for pending drafts, evaluates acceptance,
//! and signs/submits accepted drafts.
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
use solver::{config::SolverConfig, service::SigningService};
use tracing::{info, error};

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

    // Create signing service
    let signing_service = SigningService::new(config)?;
    info!("Signing service initialized");

    // Run the service loop (runs indefinitely)
    info!("Starting signing service loop...");
    if let Err(e) = signing_service.run().await {
        error!("Service error: {}", e);
        return Err(e);
    }

    Ok(())
}

