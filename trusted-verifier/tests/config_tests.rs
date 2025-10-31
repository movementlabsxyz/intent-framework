//! Unit tests for configuration management
//!
//! These tests verify configuration loading, parsing, and defaults
//! without requiring external services.

use trusted_verifier::config::Config;

/// Test that default configuration creates valid structure
/// Why: Verify default config is valid and doesn't panic
#[test]
fn test_default_config_creation() {
    let config = Config::default();
    
    assert_eq!(config.hub_chain.name, "Hub Chain");
    assert_eq!(config.hub_chain.rpc_url, "http://127.0.0.1:8080");
    assert_eq!(config.connected_chain.name, "Connected Chain");
    assert_eq!(config.connected_chain.rpc_url, "http://127.0.0.1:8082");
}

/// Test that known_accounts field exists and can be None
/// Why: Verify the new field is properly supported in the config struct
#[test]
fn test_known_accounts_field() {
    let config = Config::default();
    
    assert_eq!(config.hub_chain.known_accounts, None);
    assert_eq!(config.connected_chain.known_accounts, None);
}

/// Test that known_accounts can be set to Some(vec)
/// Why: Verify the new field accepts actual values when configured
#[test]
fn test_known_accounts_with_values() {
    let mut config = Config::default();
    
    config.hub_chain.known_accounts = Some(vec!["0xalice".to_string(), "0xbob".to_string()]);
    config.connected_chain.known_accounts = Some(vec!["0xalice2".to_string(), "0xbob2".to_string()]);
    
    assert_eq!(config.hub_chain.known_accounts, Some(vec!["0xalice".to_string(), "0xbob".to_string()]));
    assert_eq!(config.connected_chain.known_accounts, Some(vec!["0xalice2".to_string(), "0xbob2".to_string()]));
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

