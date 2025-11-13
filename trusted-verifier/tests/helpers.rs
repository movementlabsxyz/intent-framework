//! Shared test helpers for unit tests
//!
//! This module provides helper functions used by unit tests.

use ed25519_dalek::SigningKey;
use rand::RngCore;
use base64::{engine::general_purpose, Engine as _};
use trusted_verifier::config::{ApiConfig, ChainConfig, VerifierConfig, Config, EvmChainConfig};
use trusted_verifier::monitor::{RequestIntentEvent, FulfillmentEvent, EscrowEvent, ChainType};

/// Build a valid in-memory test configuration with a fresh Ed25519 keypair.
/// Keys are encoded using standard Base64 to satisfy CryptoService requirements.
#[allow(dead_code)]
pub fn build_test_config() -> Config {
    let mut rng = rand::thread_rng();
    let mut sk_bytes = [0u8; 32];
    rng.fill_bytes(&mut sk_bytes);
    let signing_key = SigningKey::from_bytes(&sk_bytes);
    let verifying_key = signing_key.verifying_key();

    let private_key_b64 = general_purpose::STANDARD.encode(signing_key.to_bytes());
    let public_key_b64 = general_purpose::STANDARD.encode(verifying_key.to_bytes());

    Config {
        hub_chain: ChainConfig {
            name: "hub".to_string(),
            rpc_url: "http://127.0.0.1:18080".to_string(),
            chain_id: 1,
            intent_module_address: "0x1".to_string(),
            escrow_module_address: None,
            known_accounts: Some(vec!["0x1".to_string()]),
        },
        connected_chain_apt: Some(ChainConfig {
            name: "connected".to_string(),
            rpc_url: "http://127.0.0.1:18082".to_string(),
            chain_id: 2,
            intent_module_address: "0x2".to_string(),
            escrow_module_address: Some("0x2".to_string()),
            known_accounts: Some(vec!["0x2".to_string()]),
        }),
        verifier: VerifierConfig {
            private_key: private_key_b64,
            public_key: public_key_b64,
            polling_interval_ms: 1000,
            validation_timeout_ms: 1000,
        },
        api: ApiConfig {
            host: "127.0.0.1".to_string(),
            port: 3999,
            cors_origins: vec![],
        },
        connected_chain_evm: None, // No connected EVM chain for unit tests
    }
}

/// Build a test configuration with EVM chain configuration.
/// Extends build_test_config() to include a populated connected_chain_evm field.
#[allow(dead_code)]
pub fn build_test_config_with_evm() -> Config {
    let mut config = build_test_config();
    config.connected_chain_evm = Some(EvmChainConfig {
        rpc_url: "http://127.0.0.1:8545".to_string(),
        escrow_contract_address: "0xEscrowAddress123".to_string(),
        chain_id: 31337,
        verifier_address: "0xVerifierAddress456".to_string(),
    });
    config
}

/// Create a base request intent event with default test values.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let request_intent = create_base_request_intent();
/// let custom_request_intent = RequestIntentEvent {
///     desired_amount: 500,
///     expiry_time: 1000000,
///     ..request_intent
/// };
/// ```
#[allow(dead_code)]
pub fn create_base_request_intent() -> RequestIntentEvent {
    RequestIntentEvent {
        intent_id: "0x0123456789abcd".to_string(), // Must be valid hex (even number of digits)
        issuer: "0xalice".to_string(),
        offered_metadata: "{\"inner\":\"0xoffered_meta\"}".to_string(),
        offered_amount: 1000,
        desired_metadata: "{\"inner\":\"0xdesired_meta\"}".to_string(),
        desired_amount: 0,
        expiry_time: 0, // Should be set explicitly in tests
        revocable: false,
        reserved_solver: Some("0xsolver".to_string()),
        connected_chain_id: Some(2),
        timestamp: 0,
    }
}

/// Create a base fulfillment event with default test values.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let fulfillment = create_base_fulfillment();
/// let custom_fulfillment = FulfillmentEvent {
///     timestamp: 1000000,
///     provided_amount: 500,
///     provided_metadata: "{\"token\":\"USDC\"}".to_string(),
///     ..fulfillment
/// };
/// ```
#[allow(dead_code)]
pub fn create_base_fulfillment() -> FulfillmentEvent {
    FulfillmentEvent {
        intent_id: "0x0123456789abcd".to_string(), // Must be valid hex (even number of digits)
        intent_address: "0xaddr".to_string(),
        solver: "0xsolver".to_string(),
        provided_metadata: "{}".to_string(),
        provided_amount: 0,
        timestamp: 0, // Should be set explicitly in tests
    }
}

/// Create a base escrow event with default test values.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let escrow = create_base_escrow_event();
/// let custom_escrow = EscrowEvent {
///     escrow_id: "0xescrow123".to_string(),
///     intent_id: "0xintent456".to_string(),
///     offered_amount: 1000,
///     ..escrow
/// };
/// ```
#[allow(dead_code)]
pub fn create_base_escrow_event() -> EscrowEvent {
    EscrowEvent {
        escrow_id: "0xescrow123".to_string(),
        intent_id: "0x0123456789abcd".to_string(), // Must be valid hex (even number of digits)
        issuer: "0xalice".to_string(),
        offered_metadata: "{\"inner\":\"0xoffered_meta\"}".to_string(),
        offered_amount: 1000,
        desired_metadata: "{\"inner\":\"0xdesired_meta\"}".to_string(),
        desired_amount: 0, // Escrow desired_amount must be 0 (validation requirement)
        expiry_time: 0, // Should be set explicitly in tests
        revocable: false,
        reserved_solver: Some("0xsolver".to_string()),
        chain_id: 2,
        chain_type: ChainType::Move,
        timestamp: 0, // Should be set explicitly in tests
    }
}

