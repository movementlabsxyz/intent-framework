//! Configuration Management Module
//!
//! This module handles loading and managing configuration for the solver service.
//! Configuration includes verifier connection, chain settings, and acceptance criteria.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::acceptance::TokenPair;

// ============================================================================
// CONFIGURATION STRUCTURES
// ============================================================================

/// Main configuration structure containing all solver service settings.
///
/// This structure holds configuration for:
/// - Verifier service connection
/// - Hub chain connection details
/// - Connected chain configuration (MVM or EVM)
/// - Acceptance criteria (token pairs and exchange rates)
/// - Solver profile and signing settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SolverConfig {
    /// Service configuration (verifier URL, polling intervals)
    pub service: ServiceConfig,
    /// Hub chain configuration (where intents are created)
    pub hub_chain: ChainConfig,
    /// Connected chain configuration (where escrows occur)
    pub connected_chain: ConnectedChainConfig,
    /// Acceptance criteria (token pairs and exchange rates)
    pub acceptance: AcceptanceConfig,
    /// Solver signing configuration
    pub solver: SolverSigningConfig,
}

/// Service-level configuration for the solver.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceConfig {
    /// Verifier API base URL (e.g., "http://127.0.0.1:3333")
    pub verifier_url: String,
    /// Polling interval for checking pending drafts in milliseconds
    pub polling_interval_ms: u64,
}

/// Configuration for a blockchain connection.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChainConfig {
    /// Human-readable name for the chain
    pub name: String,
    /// RPC endpoint URL for blockchain communication
    pub rpc_url: String,
    /// Unique chain identifier
    pub chain_id: u64,
    /// Address of the intent framework module
    pub module_address: String,
    /// Aptos/Movement CLI profile name for this chain
    pub profile: String,
}

/// Configuration for the connected chain (can be MVM or EVM).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ConnectedChainConfig {
    /// Move VM chain configuration
    #[serde(rename = "mvm")]
    Mvm(ChainConfig),
    /// EVM chain configuration
    #[serde(rename = "evm")]
    Evm(EvmChainConfig),
}

/// Configuration for an EVM-compatible chain.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvmChainConfig {
    /// Human-readable name for the chain
    pub name: String,
    /// RPC endpoint URL for EVM chain communication
    pub rpc_url: String,
    /// Chain ID (e.g., 84532 for Base Sepolia)
    pub chain_id: u64,
    /// Address of the IntentEscrow contract
    pub escrow_contract_address: String,
    /// Environment variable name containing the EVM private key
    pub private_key_env: String,
}

/// Acceptance criteria configuration.
///
/// Defines which token pairs are supported and their exchange rates.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AcceptanceConfig {
    /// Supported token pairs with exchange rates
    /// Key format: "offered_chain_id:offered_token:desired_chain_id:desired_token"
    /// Value: Exchange rate (how many offered tokens per 1 desired token)
    #[serde(flatten)]
    pub token_pairs: HashMap<String, f64>,
}

/// Solver signing configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SolverSigningConfig {
    /// Aptos/Movement CLI profile name for the solver account
    pub profile: String,
    /// Solver address (0x-prefixed hex)
    pub address: String,
}

impl SolverConfig {
    /// Loads configuration from a TOML file.
    ///
    /// This function:
    /// 1. Checks if config/solver.toml exists (or uses SOLVER_CONFIG_PATH env var)
    /// 2. If it exists, loads and parses the configuration
    /// 3. Validates the configuration
    /// 4. Converts token pair strings to TokenPair structs
    /// 5. If it doesn't exist, returns an error asking user to copy template
    ///
    /// # Returns
    ///
    /// * `Ok(SolverConfig)` - Successfully loaded and validated configuration
    /// * `Err(anyhow::Error)` - Failed to load configuration, file doesn't exist, or validation failed
    pub fn load() -> anyhow::Result<Self> {
        // Check for custom config path via environment variable (for tests)
        let config_path = std::env::var("SOLVER_CONFIG_PATH")
            .unwrap_or_else(|_| "config/solver.toml".to_string());

        if std::path::Path::new(&config_path).exists() {
            // Load existing configuration
            let content = std::fs::read_to_string(&config_path)?;
            let config: SolverConfig = toml::from_str(&content)?;
            // Validate configuration
            config.validate()?;
            Ok(config)
        } else {
            // Configuration file doesn't exist - user needs to copy template
            Err(anyhow::anyhow!(
                "Configuration file '{}' not found. Please copy the template:\n\
                cp config/solver.template.toml config/solver.toml\n\
                Then edit config/solver.toml with your actual values.",
                config_path
            ))
        }
    }

    /// Validates the configuration for consistency and correctness.
    ///
    /// Checks:
    /// - Hub and connected chains have different chain IDs
    /// - Token pair strings are in correct format
    /// - Exchange rates are positive
    ///
    /// # Returns
    ///
    /// * `Ok(())` - Configuration is valid
    /// * `Err(anyhow::Error)` - Validation failed with error message
    pub fn validate(&self) -> anyhow::Result<()> {
        // Check hub vs connected chain IDs
        let hub_chain_id = self.hub_chain.chain_id;
        let connected_chain_id = match &self.connected_chain {
            ConnectedChainConfig::Mvm(config) => config.chain_id,
            ConnectedChainConfig::Evm(config) => config.chain_id,
        };

        if hub_chain_id == connected_chain_id {
            return Err(anyhow::anyhow!(
                "Configuration error: Hub chain and connected chain have the same chain ID {}. Each chain must have a unique chain ID.",
                hub_chain_id
            ));
        }

        // Validate token pair strings and exchange rates
        for (pair_str, rate) in &self.acceptance.token_pairs {
            // Parse token pair string: "offered_chain_id:offered_token:desired_chain_id:desired_token"
            let parts: Vec<&str> = pair_str.split(':').collect();
            if parts.len() != 4 {
                return Err(anyhow::anyhow!(
                    "Invalid token pair format '{}': expected 'offered_chain_id:offered_token:desired_chain_id:desired_token'",
                    pair_str
                ));
            }

            // Validate chain IDs are numeric
            parts[0].parse::<u64>()
                .map_err(|_| anyhow::anyhow!("Invalid offered_chain_id in token pair '{}': must be a number", pair_str))?;
            parts[2].parse::<u64>()
                .map_err(|_| anyhow::anyhow!("Invalid desired_chain_id in token pair '{}': must be a number", pair_str))?;

            // Validate exchange rate is positive
            if *rate <= 0.0 {
                return Err(anyhow::anyhow!(
                    "Invalid exchange rate {} for token pair '{}': must be positive",
                    rate, pair_str
                ));
            }
        }

        Ok(())
    }

    /// Converts token pair string keys to TokenPair structs.
    ///
    /// This is a helper method for the acceptance module to use.
    ///
    /// # Returns
    ///
    /// * `HashMap<TokenPair, f64>` - Token pairs with exchange rates
    pub fn get_token_pairs(&self) -> anyhow::Result<HashMap<TokenPair, f64>> {
        let mut pairs = HashMap::new();

        for (pair_str, rate) in &self.acceptance.token_pairs {
            let parts: Vec<&str> = pair_str.split(':').collect();
            if parts.len() != 4 {
                return Err(anyhow::anyhow!(
                    "Invalid token pair format '{}': expected 'offered_chain_id:offered_token:desired_chain_id:desired_token'",
                    pair_str
                ));
            }

            let pair = TokenPair {
                offered_chain_id: parts[0].parse()?,
                offered_token: parts[1].to_string(),
                desired_chain_id: parts[2].parse()?,
                desired_token: parts[3].to_string(),
            };

            pairs.insert(pair, *rate);
        }

        Ok(pairs)
    }
}

