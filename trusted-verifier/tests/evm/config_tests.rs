//! Unit tests for EVM configuration management
//!
//! These tests verify EVM chain configuration loading, parsing, and defaults
//! without requiring external services.

use trusted_verifier::config::Config;

#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::build_test_config_with_evm;

/// Test that EvmChainConfig structure has all required fields
/// Why: Verify EvmChainConfig struct fields are properly defined
#[test]
fn test_evm_chain_config_structure() {
    use trusted_verifier::config::EvmChainConfig;

    let evm_config = EvmChainConfig {
        name: "Connected EVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8545".to_string(),
        escrow_contract_address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee".to_string(),
        chain_id: 31337,
        verifier_address: "0xffffffffffffffffffffffffffffffffffffffff".to_string(),
    };

    assert_eq!(evm_config.name, "Connected EVM Chain");
    assert_eq!(evm_config.rpc_url, "http://127.0.0.1:8545");
    assert_eq!(
        evm_config.escrow_contract_address,
        "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    );
    assert_eq!(evm_config.chain_id, 31337);
    assert_eq!(
        evm_config.verifier_address,
        "0xffffffffffffffffffffffffffffffffffffffff"
    );
}

/// Test that connected_chain_evm can be set to Some(EvmChainConfig)
/// Why: Verify connected_chain_evm accepts actual values when configured
#[test]
fn test_connected_chain_evm_with_values() {
    use trusted_verifier::config::EvmChainConfig;
    let mut config = Config::default();

    config.connected_chain_evm = Some(EvmChainConfig {
        name: "Connected EVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8545".to_string(),
        escrow_contract_address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee".to_string(),
        chain_id: 31337,
        verifier_address: "0xffffffffffffffffffffffffffffffffffffffff".to_string(),
    });

    assert!(config.connected_chain_evm.is_some());
    let evm_config = config.connected_chain_evm.as_ref().unwrap();
    assert_eq!(evm_config.name, "Connected EVM Chain");
    assert_eq!(evm_config.rpc_url, "http://127.0.0.1:8545");
    assert_eq!(
        evm_config.escrow_contract_address,
        "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    );
    assert_eq!(evm_config.chain_id, 31337);
    assert_eq!(
        evm_config.verifier_address,
        "0xffffffffffffffffffffffffffffffffffffffff"
    );
}

/// Test that EVM config can be serialized and deserialized
/// Why: Verify TOML round-trip works correctly with EVM chain config
#[test]
fn test_evm_config_serialization() {
    let config = build_test_config_with_evm();

    // Serialize to TOML
    let toml = toml::to_string(&config).expect("Should serialize to TOML");

    // Deserialize back
    let deserialized: Config = toml::from_str(&toml).expect("Should deserialize from TOML");

    // Verify EVM config fields
    assert!(deserialized.connected_chain_evm.is_some());
    let evm_config = deserialized.connected_chain_evm.as_ref().unwrap();
    assert_eq!(evm_config.name, "Connected EVM Chain");
    assert_eq!(evm_config.rpc_url, "http://127.0.0.1:8545");
    assert_eq!(
        evm_config.escrow_contract_address,
        "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    );
    assert_eq!(evm_config.chain_id, 31337);
    assert_eq!(
        evm_config.verifier_address,
        "0xffffffffffffffffffffffffffffffffffffffff"
    );
}

/// Test that EVM chain config has all fields populated correctly
/// Why: Verify build_test_config_with_evm() creates complete EVM config
#[test]
fn test_evm_chain_config_with_all_fields() {
    let config = build_test_config_with_evm();

    assert!(
        config.connected_chain_evm.is_some(),
        "EVM chain should be configured"
    );

    let evm_config = config.connected_chain_evm.as_ref().unwrap();
    assert!(!evm_config.name.is_empty(), "Name should be set");
    assert!(!evm_config.rpc_url.is_empty(), "RPC URL should be set");
    assert!(
        !evm_config.escrow_contract_address.is_empty(),
        "Escrow contract address should be set"
    );
    assert!(evm_config.chain_id > 0, "Chain ID should be set");
    assert!(
        !evm_config.verifier_address.is_empty(),
        "Verifier address should be set"
    );

    // Verify specific values from build_test_config_with_evm
    assert_eq!(evm_config.name, "Connected EVM Chain");
    assert_eq!(evm_config.rpc_url, "http://127.0.0.1:8545");
    assert_eq!(
        evm_config.escrow_contract_address,
        "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    );
    assert_eq!(evm_config.chain_id, 31337);
    assert_eq!(
        evm_config.verifier_address,
        "0xffffffffffffffffffffffffffffffffffffffff"
    );
}

/// Test that config with EVM chain can be loaded (structure validation)
/// Why: Verify EVM config structure is valid for loading
#[test]
fn test_evm_config_loading() {
    let config = build_test_config_with_evm();

    // Verify config structure is valid
    assert!(config.connected_chain_evm.is_some());

    // Verify all required fields are present
    let evm_config = config.connected_chain_evm.as_ref().unwrap();
    assert!(!evm_config.name.is_empty());
    assert!(!evm_config.rpc_url.is_empty());
    assert!(!evm_config.escrow_contract_address.is_empty());
    assert!(evm_config.chain_id > 0);
    assert!(!evm_config.verifier_address.is_empty());

    // Verify config can be cloned (tests structure validity)
    let cloned_config = config.clone();
    assert!(cloned_config.connected_chain_evm.is_some());
}
