//! Unit tests for configuration management
//!
//! These tests verify configuration loading, parsing, and defaults
//! without requiring external services.

use trusted_verifier::config::{ChainConfig, Config, EvmChainConfig};
use trusted_verifier::monitor::ChainType;
use trusted_verifier::validator::{get_chain_type_from_chain_id, normalize_address};

/// Test that default configuration creates valid structure
/// Why: Verify default config is valid and doesn't panic
#[test]
fn test_default_config_creation() {
    let config = Config::default();

    assert_eq!(config.hub_chain.name, "Hub Chain");
    assert_eq!(config.hub_chain.rpc_url, "http://127.0.0.1:8080");
    assert!(
        config.connected_chain_mvm.is_none(),
        "Default config should have no connected Move VM chain"
    );
    assert!(
        config.connected_chain_evm.is_none(),
        "Default config should have no connected EVM chain"
    );
}

/// Test that known_accounts field exists and can be None
/// Why: Verify the new field is properly supported in the config struct
#[test]
fn test_known_accounts_field() {
    let config = Config::default();

    assert_eq!(config.hub_chain.known_accounts, None);
    assert!(config.connected_chain_mvm.is_none());
}

/// Test that known_accounts can be set to Some(vec)
/// Why: Verify the new field accepts actual values when configured
#[test]
fn test_known_accounts_with_values() {
    let mut config = Config::default();

    config.hub_chain.known_accounts = Some(vec!["0xalice".to_string(), "0xbob".to_string()]);

    assert_eq!(
        config.hub_chain.known_accounts,
        Some(vec!["0xalice".to_string(), "0xbob".to_string()])
    );
}

/// Test that connected_chain_mvm can be set to Some(ChainConfig)
/// Why: Verify connected_chain_mvm accepts actual values when configured
#[test]
fn test_connected_chain_mvm_with_values() {
    use trusted_verifier::config::ChainConfig;
    let mut config = Config::default();

    config.connected_chain_mvm = Some(ChainConfig {
        name: "Connected Move VM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8082".to_string(),
        chain_id: 2,
        intent_module_address: "0x123".to_string(),
        escrow_module_address: Some("0x123".to_string()),
        known_accounts: Some(vec!["0xalice2".to_string(), "0xbob2".to_string()]),
    });

    assert_eq!(
        config.connected_chain_mvm.as_ref().unwrap().name,
        "Connected Move VM Chain"
    );
    assert_eq!(
        config.connected_chain_mvm.as_ref().unwrap().known_accounts,
        Some(vec!["0xalice2".to_string(), "0xbob2".to_string()])
    );
}

/// Test that config can be serialized and deserialized
/// Why: Verify TOML round-trip works correctly
#[test]
fn test_config_serialization() {
    let config = Config::default();

    // Serialize to TOML
    let toml = toml::to_string(&config).expect("Should serialize to TOML");

    // Deserialize back
    let deserialized: Config = toml::from_str(&toml).expect("Should deserialize from TOML");

    assert_eq!(config.hub_chain.name, deserialized.hub_chain.name);
    assert_eq!(config.hub_chain.rpc_url, deserialized.hub_chain.rpc_url);
}

// ============================================================================
// CHAIN TYPE UTILITIES TESTS
// ============================================================================

/// Test that get_chain_type_from_chain_id returns Evm for EVM chain ID
/// Why: Verify the function correctly identifies EVM chains from chain ID
#[test]
fn test_get_chain_type_from_chain_id_evm() {
    let mut config = Config::default();
    config.connected_chain_evm = Some(EvmChainConfig {
        name: "EVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8545".to_string(),
        escrow_contract_address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee".to_string(),
        chain_id: 31337,
        verifier_address: "0xffffffffffffffffffffffffffffffffffffffff".to_string(),
    });

    let result = get_chain_type_from_chain_id(31337, &config);
    assert!(result.is_ok(), "Should successfully identify EVM chain");
    assert_eq!(result.unwrap(), ChainType::Evm);
}

/// Test that get_chain_type_from_chain_id returns Mvm for MVM chain ID
/// Why: Verify the function correctly identifies MVM chains from chain ID
#[test]
fn test_get_chain_type_from_chain_id_mvm() {
    let mut config = Config::default();
    config.connected_chain_mvm = Some(ChainConfig {
        name: "MVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8082".to_string(),
        chain_id: 2,
        intent_module_address: "0x123".to_string(),
        escrow_module_address: Some("0x123".to_string()),
        known_accounts: None,
    });

    let result = get_chain_type_from_chain_id(2, &config);
    assert!(result.is_ok(), "Should successfully identify MVM chain");
    assert_eq!(result.unwrap(), ChainType::Mvm);
}

/// Test that get_chain_type_from_chain_id returns error for unknown chain ID
/// Why: Verify the function correctly rejects chain IDs that don't match any configured chain
#[test]
fn test_get_chain_type_from_chain_id_unknown() {
    let config = Config::default();

    let result = get_chain_type_from_chain_id(999, &config);
    assert!(result.is_err(), "Should return error for unknown chain ID");
    assert!(result.unwrap_err().to_string().contains("does not match any configured connected chain"));
}

/// Test that get_chain_type_from_chain_id returns error when EVM and MVM have same chain ID
/// Why: Verify the function rejects invalid configurations with duplicate chain IDs
#[test]
fn test_get_chain_type_from_chain_id_duplicate_chain_id_error() {
    let mut config = Config::default();
    // Set both EVM and MVM to same chain_id (invalid configuration)
    config.connected_chain_evm = Some(EvmChainConfig {
        name: "EVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8545".to_string(),
        escrow_contract_address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee".to_string(),
        chain_id: 100,
        verifier_address: "0xffffffffffffffffffffffffffffffffffffffff".to_string(),
    });
    config.connected_chain_mvm = Some(ChainConfig {
        name: "MVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8082".to_string(),
        chain_id: 100,
        intent_module_address: "0x123".to_string(),
        escrow_module_address: Some("0x123".to_string()),
        known_accounts: None,
    });

    // Should return error for duplicate chain IDs
    let result = get_chain_type_from_chain_id(100, &config);
    assert!(result.is_err(), "Should reject duplicate chain IDs");
    assert!(result.unwrap_err().to_string().contains("same chain ID"), "Error message should mention duplicate chain ID");
}

// ============================================================================
// CONFIG VALIDATION TESTS
// ============================================================================

/// Test that config.validate() returns error when hub and MVM chains have same chain ID
/// Why: Verify configuration validation catches duplicate chain IDs at load time
#[test]
fn test_config_validate_hub_mvm_duplicate_chain_id() {
    let mut config = Config::default();
    config.hub_chain.chain_id = 100;
    config.connected_chain_mvm = Some(ChainConfig {
        name: "MVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8082".to_string(),
        chain_id: 100, // Same as hub
        intent_module_address: "0x123".to_string(),
        escrow_module_address: Some("0x123".to_string()),
        known_accounts: None,
    });

    let result = config.validate();
    assert!(result.is_err(), "Should reject duplicate chain IDs");
    assert!(result.unwrap_err().to_string().contains("Hub chain and connected MVM chain have the same chain ID"), "Error message should mention hub and MVM duplicate");
}

/// Test that config.validate() returns error when hub and EVM chains have same chain ID
/// Why: Verify configuration validation catches duplicate chain IDs at load time
#[test]
fn test_config_validate_hub_evm_duplicate_chain_id() {
    let mut config = Config::default();
    config.hub_chain.chain_id = 100;
    config.connected_chain_evm = Some(EvmChainConfig {
        name: "EVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8545".to_string(),
        escrow_contract_address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee".to_string(),
        chain_id: 100, // Same as hub
        verifier_address: "0xffffffffffffffffffffffffffffffffffffffff".to_string(),
    });

    let result = config.validate();
    assert!(result.is_err(), "Should reject duplicate chain IDs");
    assert!(result.unwrap_err().to_string().contains("Hub chain and connected EVM chain have the same chain ID"), "Error message should mention hub and EVM duplicate");
}

/// Test that config.validate() returns error when MVM and EVM chains have same chain ID
/// Why: Verify configuration validation catches duplicate chain IDs at load time
#[test]
fn test_config_validate_mvm_evm_duplicate_chain_id() {
    let mut config = Config::default();
    config.connected_chain_mvm = Some(ChainConfig {
        name: "MVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8082".to_string(),
        chain_id: 100,
        intent_module_address: "0x123".to_string(),
        escrow_module_address: Some("0x123".to_string()),
        known_accounts: None,
    });
    config.connected_chain_evm = Some(EvmChainConfig {
        name: "EVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8545".to_string(),
        escrow_contract_address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee".to_string(),
        chain_id: 100, // Same as MVM
        verifier_address: "0xffffffffffffffffffffffffffffffffffffffff".to_string(),
    });

    let result = config.validate();
    assert!(result.is_err(), "Should reject duplicate chain IDs");
    assert!(result.unwrap_err().to_string().contains("Connected MVM chain and connected EVM chain have the same chain ID"), "Error message should mention MVM and EVM duplicate");
}

/// Test that config.validate() succeeds when all chain IDs are unique
/// Why: Verify configuration validation passes for valid configurations
#[test]
fn test_config_validate_unique_chain_ids() {
    let mut config = Config::default();
    config.hub_chain.chain_id = 1;
    config.connected_chain_mvm = Some(ChainConfig {
        name: "MVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8082".to_string(),
        chain_id: 2, // Different from hub
        intent_module_address: "0x123".to_string(),
        escrow_module_address: Some("0x123".to_string()),
        known_accounts: None,
    });
    config.connected_chain_evm = Some(EvmChainConfig {
        name: "EVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8545".to_string(),
        escrow_contract_address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee".to_string(),
        chain_id: 31337, // Different from hub and MVM
        verifier_address: "0xffffffffffffffffffffffffffffffffffffffff".to_string(),
    });

    let result = config.validate();
    assert!(result.is_ok(), "Should accept unique chain IDs");
}

// ============================================================================
// ADDRESS NORMALIZATION TESTS
// ============================================================================

/// Test that normalize_address pads Move VM addresses with leading zeros
/// Why: Move VM addresses can be serialized without leading zeros (63 chars), need to pad to 64
#[test]
fn test_normalize_address_mvm_pads_short_address() {
    let address = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"; // 63 chars
    let normalized = normalize_address(address, ChainType::Mvm);

    assert_eq!(
        normalized.len(),
        66,
        "Should be 0x + 64 hex chars = 66 total"
    );
    assert!(normalized.starts_with("0x"), "Should have 0x prefix");
    assert_eq!(&normalized[2..3], "0", "Should be padded with leading zero");
    assert_eq!(
        &normalized[3..],
        "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        "Rest should match"
    );
}

/// Test that normalize_address doesn't pad Move VM addresses that are already 64 chars
/// Why: Addresses that are already correct length should not be modified
#[test]
fn test_normalize_address_mvm_keeps_full_address() {
    let address = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; // 64 chars
    let normalized = normalize_address(address, ChainType::Mvm);

    assert_eq!(normalized, address, "Should remain unchanged");
}

/// Test that normalize_address handles Move VM addresses without 0x prefix
/// Why: Addresses may come without prefix, should add it
#[test]
fn test_normalize_address_mvm_adds_prefix() {
    let address = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"; // 63 chars, no prefix
    let normalized = normalize_address(address, ChainType::Mvm);

    assert!(normalized.starts_with("0x"), "Should add 0x prefix");
    assert_eq!(
        normalized.len(),
        66,
        "Should be 0x + 64 hex chars = 66 total"
    );
    assert_eq!(&normalized[2..3], "0", "Should be padded with leading zero");
}

/// Test that normalize_address pads EVM addresses correctly
/// Why: EVM addresses should be padded to 40 hex chars (20 bytes)
#[test]
fn test_normalize_address_evm_pads_short_address() {
    let address = "0xccccccccccccccccccccccccccccccccccccccc"; // 39 chars
    let normalized = normalize_address(address, ChainType::Evm);

    assert_eq!(
        normalized.len(),
        42,
        "Should be 0x + 40 hex chars = 42 total"
    );
    assert!(normalized.starts_with("0x"), "Should have 0x prefix");
    assert_eq!(&normalized[2..3], "0", "Should be padded with leading zero");
}

/// Test that normalize_address handles EVM addresses correctly
/// Why: EVM addresses are 40 hex chars, should not be padded if already correct
#[test]
fn test_normalize_address_evm_keeps_full_address() {
    let address = "0xdddddddddddddddddddddddddddddddddddddddd"; // 40 chars
    let normalized = normalize_address(address, ChainType::Evm);

    assert_eq!(normalized, address, "Should remain unchanged");
}
