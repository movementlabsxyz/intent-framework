//! Unit tests module
//!
//! This module contains unit tests that don't require external services.

pub mod crypto_tests;
pub mod config_tests;
pub mod monitor_tests;
pub mod cross_chain_tests;

// ---------------------------------------------------------------------------
// Shared test helpers
// ---------------------------------------------------------------------------

use ed25519_dalek::SigningKey;
use rand::RngCore;
use base64::{engine::general_purpose, Engine as _};
use trusted_verifier::config::{ApiConfig, ChainConfig, VerifierConfig, Config};

/// Build a valid in-memory test configuration with a fresh Ed25519 keypair.
/// Keys are encoded using standard Base64 to satisfy CryptoService requirements.
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
        connected_chain: ChainConfig {
            name: "connected".to_string(),
            rpc_url: "http://127.0.0.1:18082".to_string(),
            chain_id: 2,
            intent_module_address: "0x2".to_string(),
            escrow_module_address: Some("0x2".to_string()),
            known_accounts: Some(vec!["0x2".to_string()]),
        },
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
    }
}

