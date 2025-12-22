//! Unit tests for configuration module

#[path = "helpers.rs"]
mod test_helpers;
use test_helpers::{
    create_default_connected_mvm_chain_config, create_default_solver_config, create_default_token_pair,
    DUMMY_ESCROW_CONTRACT_ADDR_EVM, DUMMY_TOKEN_ADDR_EVM, DUMMY_TOKEN_ADDR_MVM_CON, DUMMY_TOKEN_ADDR_MVM_HUB,
};

use solver::config::{AcceptanceConfig, ChainConfig, ConnectedChainConfig, SolverConfig};
use std::collections::HashMap;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a minimal valid SolverConfig for testing
fn create_test_config() -> SolverConfig {
    let mut token_pairs = HashMap::new();
    token_pairs.insert(
        format!("1:{}:2:{}", DUMMY_TOKEN_ADDR_MVM_HUB, DUMMY_TOKEN_ADDR_MVM_CON),
        1.0,
    );
    
    SolverConfig {
        acceptance: AcceptanceConfig {
            token_pairs,
        },
        ..create_default_solver_config()
    }
}

// ============================================================================
// VALIDATION TESTS
// ============================================================================

/// What is tested: SolverConfig::validate() accepts valid configuration
/// Why: Ensure valid configs pass validation
#[test]
fn test_config_validation_success() {
    let config = create_test_config();
    assert!(config.validate().is_ok());
}

/// What is tested: SolverConfig::validate() rejects duplicate chain IDs
/// Why: Ensure hub and connected chains have different chain IDs
#[test]
fn test_config_validation_duplicate_chain_ids() {
    let mut config = create_test_config();
    // Set connected chain to same ID as hub
    config.connected_chain = ConnectedChainConfig::Mvm(ChainConfig {
        chain_id: 1, // Same as hub chain
        ..create_default_connected_mvm_chain_config()
    });

    let result = config.validate();
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("same chain ID"));
}

/// What is tested: SolverConfig::validate() rejects invalid token pair format
/// Why: Ensure token pair strings are in correct format
#[test]
fn test_config_validation_invalid_token_pair_format() {
    let mut config = create_test_config();
    config.acceptance.token_pairs.clear();
    config.acceptance.token_pairs.insert(
        "invalid-format".to_string(), // Missing colons
        1.0,
    );

    let result = config.validate();
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("Invalid token pair format"));
}

/// What is tested: SolverConfig::validate() rejects non-numeric chain IDs in token pairs
/// Why: Ensure chain IDs in token pairs are valid numbers
#[test]
fn test_config_validation_invalid_chain_id_in_token_pair() {
    let mut config = create_test_config();
    config.acceptance.token_pairs.clear();
    config.acceptance.token_pairs.insert(
        "invalid:0xaaa:2:0xbbb".to_string(), // Invalid chain ID
        1.0,
    );

    let result = config.validate();
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("Invalid offered_chain_id"));
}

/// What is tested: SolverConfig::validate() rejects non-positive exchange rates
/// Why: Ensure exchange rates are positive
#[test]
fn test_config_validation_negative_exchange_rate() {
    let mut config = create_test_config();
    config.acceptance.token_pairs.clear();
    config.acceptance.token_pairs.insert(
        "1:0xaaa:2:0xbbb".to_string(),
        -1.0, // Negative rate
    );

    let result = config.validate();
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("must be positive"));
}

/// What is tested: SolverConfig::validate() rejects zero exchange rate
/// Why: Ensure exchange rates are positive (not zero)
#[test]
fn test_config_validation_zero_exchange_rate() {
    let mut config = create_test_config();
    config.acceptance.token_pairs.clear();
    config.acceptance.token_pairs.insert(
        "1:0xaaa:2:0xbbb".to_string(),
        0.0, // Zero rate
    );

    let result = config.validate();
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("must be positive"));
}

// ============================================================================
// TOKEN PAIR CONVERSION TESTS
// ============================================================================

/// What is tested: SolverConfig::get_token_pairs() converts string keys to TokenPair structs
/// Why: Ensure token pair strings are correctly parsed into TokenPair structs
#[test]
fn test_get_token_pairs_success() {
    let config = create_test_config();
    let pairs = config.get_token_pairs().unwrap();

    assert_eq!(pairs.len(), 1);
    
    let expected_pair = create_default_token_pair();
    
    assert!(pairs.contains_key(&expected_pair));
    assert_eq!(pairs[&expected_pair], 1.0);
}

/// What is tested: SolverConfig::get_token_pairs() handles multiple token pairs
/// Why: Ensure multiple token pairs are correctly converted
#[test]
fn test_get_token_pairs_multiple() {
    let mut config = create_test_config();
    config.acceptance.token_pairs.insert(
        "2:0xbbb:1:0xaaa".to_string(),
        0.5,
    );

    let pairs = config.get_token_pairs().unwrap();
    assert_eq!(pairs.len(), 2);
}

/// What is tested: SolverConfig::get_token_pairs() rejects invalid token pair format
/// Why: Ensure invalid formats are caught during conversion
#[test]
fn test_get_token_pairs_invalid_format() {
    let mut config = create_test_config();
    config.acceptance.token_pairs.clear();
    config.acceptance.token_pairs.insert(
        "invalid-format".to_string(),
        1.0,
    );

    let result = config.get_token_pairs();
    assert!(result.is_err());
}

/// What is tested: SolverConfig::get_token_pairs() handles token addresses
/// Why: Ensure all tokens use their actual addresses (hex format)
#[test]
fn test_get_token_pairs_token_address() {
    let mut config = create_test_config();
    config.acceptance.token_pairs.clear();
    // Token addresses in the config use hex format
    config.acceptance.token_pairs.insert(
        format!("1:{}:2:{}", DUMMY_TOKEN_ADDR_MVM_HUB, DUMMY_TOKEN_ADDR_EVM),
        0.5,
    );

    let pairs = config.get_token_pairs().unwrap();
    assert_eq!(pairs.len(), 1);
    
    use solver::TokenPair;
    let expected_pair = TokenPair {
        desired_token: DUMMY_TOKEN_ADDR_EVM.to_string(), // Connected chain token (EVM format, different from default)
        ..create_default_token_pair() // Uses default for offered_token and chain_id fields
    };
    
    assert!(pairs.contains_key(&expected_pair));
    assert_eq!(pairs[&expected_pair], 0.5);
}

// ============================================================================
// TOML SERIALIZATION/DESERIALIZATION TESTS
// ============================================================================

/// What is tested: SolverConfig can be serialized to and deserialized from TOML
/// Why: Ensure config structs work with TOML format
#[test]
fn test_config_toml_roundtrip() {
    let config = create_test_config();
    
    // Serialize to TOML
    let toml_str = toml::to_string(&config).unwrap();
    
    // Deserialize from TOML
    let deserialized: SolverConfig = toml::from_str(&toml_str).unwrap();
    
    // Verify key fields match
    assert_eq!(deserialized.service.verifier_url, config.service.verifier_url);
    assert_eq!(deserialized.hub_chain.chain_id, config.hub_chain.chain_id);
    assert_eq!(deserialized.acceptance.token_pairs.len(), config.acceptance.token_pairs.len());
}

/// What is tested: ConnectedChainConfig can deserialize MVM type
/// Why: Ensure MVM chain config is correctly parsed from TOML
#[test]
fn test_connected_chain_mvm_deserialization() {
    let toml_str = r#"
type = "mvm"
name = "connected-chain"
rpc_url = "http://127.0.0.1:8082/v1"
chain_id = 2
module_addr = "0x2"
profile = "connected-profile"
"#;

    let chain: ConnectedChainConfig = toml::from_str(toml_str).unwrap();
    
    match chain {
        ConnectedChainConfig::Mvm(config) => {
            assert_eq!(config.chain_id, 2);
            assert_eq!(config.name, "connected-chain");
        }
        ConnectedChainConfig::Evm(_) => panic!("Expected MVM config"),
    }
}

/// What is tested: ConnectedChainConfig can deserialize EVM type
/// Why: Ensure EVM chain config is correctly parsed from TOML
#[test]
fn test_connected_chain_evm_deserialization() {
    let toml_str = format!(r#"
type = "evm"
name = "Connected EVM Chain"
rpc_url = "https://sepolia.base.org"
chain_id = 84532
escrow_contract_addr = "{}"
private_key_env = "BASE_SOLVER_PRIVATE_KEY"
"#, DUMMY_ESCROW_CONTRACT_ADDR_EVM);

    let chain: ConnectedChainConfig = toml::from_str(&toml_str).unwrap();
    
    match chain {
        ConnectedChainConfig::Evm(config) => {
            assert_eq!(config.chain_id, 84532);
            assert_eq!(config.name, "Connected EVM Chain");
            assert_eq!(config.escrow_contract_addr, DUMMY_ESCROW_CONTRACT_ADDR_EVM);
            assert_eq!(config.private_key_env, "BASE_SOLVER_PRIVATE_KEY");
        }
        ConnectedChainConfig::Mvm(_) => panic!("Expected EVM config"),
    }
}

// ============================================================================
// FILE LOADING TESTS
// ============================================================================

/// What is tested: SolverConfig::load() loads configuration from TOML file
/// Why: Ensure config can be loaded from actual TOML file
#[test]
fn test_config_load_from_file() {
    use std::fs;
    
    // Create a temporary config file
    let test_config_dir = ".tmp/test_config";
    let test_config_file = format!("{}/solver.toml", test_config_dir);
    
    // Ensure directory exists
    fs::create_dir_all(test_config_dir).unwrap();
    
    // Write test config
    let toml_content = r#"
[service]
verifier_url = "http://127.0.0.1:3333"
polling_interval_ms = 2000

[hub_chain]
name = "hub-chain"
rpc_url = "http://127.0.0.1:8080/v1"
chain_id = 1
module_addr = "0x1"
profile = "hub-profile"

[connected_chain]
type = "mvm"
name = "connected-chain"
rpc_url = "http://127.0.0.1:8082/v1"
chain_id = 2
module_addr = "0x2"
profile = "connected-profile"

[acceptance]
"1:0xaaa:2:0xbbb" = 1.0

[solver]
profile = "hub-profile"
address = "0xccc"
"#;
    
    fs::write(&test_config_file, toml_content).unwrap();
    
    // Set environment variable to point to test config
    std::env::set_var("SOLVER_CONFIG_PATH", &test_config_file);
    
    // Load config
    let config = SolverConfig::load().unwrap();
    
    // Verify loaded values
    assert_eq!(config.service.verifier_url, "http://127.0.0.1:3333");
    assert_eq!(config.hub_chain.chain_id, 1);
    assert_eq!(config.acceptance.token_pairs.len(), 1);
    
    // Cleanup
    std::env::remove_var("SOLVER_CONFIG_PATH");
    fs::remove_file(&test_config_file).unwrap();
    fs::remove_dir(test_config_dir).unwrap();
}

/// What is tested: SolverConfig::load() returns error when file doesn't exist
/// Why: Ensure proper error message when config file is missing
#[test]
fn test_config_load_file_not_found() {
    // Use load_from_path directly with explicit non-existent path
    // to avoid parallel test interference with environment variables
    let result = SolverConfig::load_from_path(Some("/tmp/nonexistent/solver.toml"));
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("not found"));
}

