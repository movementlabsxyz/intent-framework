//! Configuration Management Module
//! 
//! This module handles loading and managing configuration for the trusted verifier service.
//! Configuration includes chain endpoints, verifier keys, API settings, and validation parameters.

use serde::{Deserialize, Serialize};

// ============================================================================
// CONFIGURATION STRUCTURES
// ============================================================================

/// Main configuration structure containing all service settings.
/// 
/// This structure holds configuration for:
/// - Hub chain connection details
/// - Connected Aptos chain connection details (optional, for Aptos escrow chains)
/// - Connected EVM chain configuration (optional, for EVM escrow chains)
/// - Verifier cryptographic keys and settings
/// - API server configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Hub chain configuration (where intents are created)
    pub hub_chain: ChainConfig,
    /// Connected Aptos chain configuration (optional, where escrow events occur on Aptos)
    #[serde(default)]
    pub connected_chain_apt: Option<ChainConfig>,
    /// Connected EVM chain configuration (optional, for escrow on EVM)
    #[serde(default)]
    pub connected_chain_evm: Option<EvmChainConfig>,
    /// Verifier-specific configuration (keys, timeouts, etc.)
    pub verifier: VerifierConfig,
    /// API server configuration (host, port, CORS settings)
    pub api: ApiConfig,
}

/// Configuration for a blockchain connection.
/// 
/// Contains all necessary information to connect to and interact with a blockchain,
/// including RPC endpoints, chain identifiers, and module addresses.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChainConfig {
    /// Human-readable name for the chain
    pub name: String,
    /// RPC endpoint URL for blockchain communication
    pub rpc_url: String,
    /// Unique chain identifier
    pub chain_id: u64,
    /// Address of the intent framework module
    pub intent_module_address: String,
    /// Address of the escrow module (optional for hub chain)
    pub escrow_module_address: Option<String>,
    /// Known test accounts to poll for events
    pub known_accounts: Option<Vec<String>>,
}

/// Configuration for an EVM-compatible chain (Ethereum, Hardhat, etc.)
/// 
/// Used when escrows are hosted on EVM chains instead of Move-based chains.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvmChainConfig {
    /// RPC endpoint URL for EVM chain communication
    pub rpc_url: String,
    /// Address of the IntentEscrow contract (single contract, one escrow per intentId)
    pub escrow_contract_address: String,
    /// Chain ID (e.g., 31337 for Hardhat, 1 for Ethereum mainnet)
    pub chain_id: u64,
    /// Verifier address (ECDSA public key as Ethereum address)
    pub verifier_address: String,
}

/// Verifier-specific configuration including cryptographic keys and timing parameters.
/// 
/// This configuration is critical for the verifier's operation and security.
/// The private key must be kept secure and never exposed.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerifierConfig {
    /// Ed25519 private key for signing approvals (base64 encoded)
    pub private_key: String,
    /// Ed25519 public key for signature verification (base64 encoded)
    pub public_key: String,
    /// Polling interval for event monitoring in milliseconds
    pub polling_interval_ms: u64,
    /// Timeout for validation operations in milliseconds
    pub validation_timeout_ms: u64,
}

/// API server configuration for external communication.
/// 
/// Controls how the verifier service exposes its REST API endpoints
/// and handles cross-origin requests.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiConfig {
    /// Host address to bind the API server to
    pub host: String,
    /// Port number to bind the API server to
    pub port: u16,
    /// Allowed CORS origins for cross-origin requests
    pub cors_origins: Vec<String>,
}

// ============================================================================
// CONFIGURATION LOADING AND MANAGEMENT
// ============================================================================

impl Config {
    /// Loads configuration from the TOML file.
    /// 
    /// This function:
    /// 1. Checks if config/verifier.toml exists
    /// 2. If it exists, loads and parses the configuration
    /// 3. If it doesn't exist, returns an error asking user to copy template
    /// 
    /// # Returns
    /// 
    /// - `Ok(Config)` - Successfully loaded configuration
    /// - `Err(anyhow::Error)` - Failed to load configuration or file doesn't exist
    pub fn load() -> anyhow::Result<Self> {
        // Check for custom config path via environment variable (for tests)
        let config_path = std::env::var("VERIFIER_CONFIG_PATH")
            .unwrap_or_else(|_| "config/verifier.toml".to_string());
        
        if std::path::Path::new(&config_path).exists() {
            // Load existing configuration
            let content = std::fs::read_to_string(&config_path)?;
            let config: Config = toml::from_str(&content)?;
            Ok(config)
        } else {
            // Configuration file doesn't exist - user needs to copy template
            Err(anyhow::anyhow!(
                "Configuration file '{}' not found. Please copy the template:\n\
                cp config/verifier.template.toml config/verifier.toml\n\
                Then edit config/verifier.toml with your actual values.",
                config_path
            ))
        }
    }
    
    /// Creates a default configuration with placeholder values.
    /// 
    /// This configuration is suitable for local development and testing.
    /// For production use, all placeholder values must be replaced with
    /// actual chain URLs, module addresses, and cryptographic keys.
    #[allow(dead_code)]
    pub fn default() -> Self {
        Self {
            hub_chain: ChainConfig {
                name: "Hub Chain".to_string(),
                rpc_url: "http://127.0.0.1:8080".to_string(),
                chain_id: 1,
                intent_module_address: "0x123".to_string(),
                escrow_module_address: None,
                known_accounts: None, // Should be set in config/verifier.toml
            },
            connected_chain_apt: None, // Optional connected Aptos chain configuration
            verifier: VerifierConfig {
                private_key: "REPLACE_WITH_PRIVATE_KEY".to_string(),
                public_key: "REPLACE_WITH_PUBLIC_KEY".to_string(),
                polling_interval_ms: 2000,
                validation_timeout_ms: 30000,
            },
            api: ApiConfig {
                host: "127.0.0.1".to_string(),
                port: 3333,
                cors_origins: vec!["http://localhost:3333".to_string()],
            },
            connected_chain_evm: None, // Optional connected EVM chain configuration
        }
    }
}
