//! Shared test helpers for unit tests
//!
//! This module provides helper functions used by unit tests.

use base64::{engine::general_purpose, Engine as _};
use ed25519_dalek::SigningKey;
use rand::RngCore;
use trusted_verifier::config::{ApiConfig, ChainConfig, Config, EvmChainConfig, VerifierConfig};
use trusted_verifier::evm_client::EvmTransaction;
use trusted_verifier::monitor::{ChainType, EscrowEvent, FulfillmentEvent, IntentEvent};
use trusted_verifier::mvm_client::MvmTransaction;
use trusted_verifier::validator::FulfillmentTransactionParams;

/// Build a valid in-memory test configuration with a fresh Ed25519 keypair.
/// Keys are encoded using standard Base64 to satisfy CryptoService requirements.
#[allow(dead_code)]
pub fn build_test_config_with_mvm() -> Config {
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
        connected_chain_mvm: Some(ChainConfig {
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
/// Extends build_test_config_with_mvm() to include a populated connected_chain_evm field.
#[allow(dead_code)]
pub fn build_test_config_with_evm() -> Config {
    let mut config = build_test_config_with_mvm();
    config.connected_chain_evm = Some(EvmChainConfig {
        name: "Connected EVM Chain".to_string(),
        rpc_url: "http://127.0.0.1:8545".to_string(),
        escrow_contract_address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee".to_string(), // EVM contract address (40 hex chars)
        chain_id: 31337,
        verifier_address: "0xffffffffffffffffffffffffffffffffffffffff".to_string(), // EVM address (40 hex chars)
    });
    config
}

/// Create a base intent event with default test values for Move VM connected chain.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let intent = create_base_intent_mvm();
/// let custom_intent = IntentEvent {
///     desired_amount: 500,
///     expiry_time: 1000000,
///     ..intent
/// };
/// ```
#[allow(dead_code)]
pub fn create_base_intent_mvm() -> IntentEvent {
    IntentEvent {
        intent_id: "0x1111111111111111111111111111111111111111111111111111111111111111".to_string(), // Must be valid hex (even number of digits)
        requester: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(), // Hub chain requester (Move VM format, 32 bytes)
        offered_metadata: "{\"inner\":\"offered_meta\"}".to_string(),
        offered_amount: 1000,
        desired_metadata: "{\"inner\":\"desired_meta\"}".to_string(),
        desired_amount: 0,
        expiry_time: 0, // Should be set explicitly in tests
        revocable: false,
        reserved_solver: Some(
            "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(),
        ), // Move VM address format (32 bytes)
        connected_chain_id: Some(2),
        requester_address_connected_chain: Some(
            "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        ), // Required for outflow intents (connected_chain_id is Some). Move VM address format (32 bytes)
        timestamp: 0,
    }
}

/// Create a base intent event with default test values for EVM connected chain.
/// This uses `create_base_intent_mvm()` as a base and overrides EVM-specific fields.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let intent = create_base_intent_evm();
/// let custom_intent = IntentEvent {
///     desired_amount: 500,
///     expiry_time: 1000000,
///     ..intent
/// };
/// ```
#[allow(dead_code)]
pub fn create_base_intent_evm() -> IntentEvent {
    IntentEvent {
        reserved_solver: Some("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string()), // EVM address format (20 bytes)
        connected_chain_id: Some(31337), // EVM chain ID (matches build_test_config_with_evm)
        requester_address_connected_chain: Some(
            "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        ), // EVM address format (20 bytes)
        ..create_base_intent_mvm()
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
        intent_id: "0x1111111111111111111111111111111111111111111111111111111111111111".to_string(), // Must be valid hex (even number of digits)
        intent_address: "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
            .to_string(), // Intent object address (64 hex chars for Move VM)
        solver: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(),
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
///     escrow_id: "0x2222222222222222222222222222222222222222222222222222222222222222".to_string(),
///     intent_id: "0x1111111111111111111111111111111111111111111111111111111111111111".to_string(),
///     offered_amount: 1000,
///     ..escrow
/// };
/// ```
#[allow(dead_code)]
pub fn create_base_escrow_event() -> EscrowEvent {
    EscrowEvent {
        escrow_id: "0x2222222222222222222222222222222222222222222222222222222222222222".to_string(), // Escrow address (64 hex chars for Move VM)
        intent_id: "0x1111111111111111111111111111111111111111111111111111111111111111".to_string(), // Must be valid hex (even number of digits)
        issuer: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(), // EscrowEvent.issuer is the requester who created the escrow and locked funds (for inflow escrows on connected chain)
        offered_metadata: "{\"inner\":\"offered_meta\"}".to_string(),
        offered_amount: 1000,
        desired_metadata: "{\"inner\":\"desired_meta\"}".to_string(),
        desired_amount: 0, // Escrow desired_amount must be 0 (validation requirement)
        expiry_time: 0,    // Should be set explicitly in tests
        revocable: false,
        reserved_solver: Some(
            "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(),
        ),
        chain_id: 2,
        chain_type: ChainType::Mvm,
        timestamp: 0, // Should be set explicitly in tests
    }
}

/// Create a base fulfillment transaction params with default test values for Move VM connected chain.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let base = create_base_fulfillment_transaction_params_mvm();
/// let custom = FulfillmentTransactionParams {
///     intent_id: "0xcustom".to_string(),
///     amount: 5000,
///     ..base
/// };
/// ```
#[allow(dead_code)]
pub fn create_base_fulfillment_transaction_params_mvm() -> FulfillmentTransactionParams {
    FulfillmentTransactionParams {
        intent_id: "0x1111111111111111111111111111111111111111111111111111111111111111".to_string(), // Must be valid hex (even number of digits)
        recipient: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(), // Requester who receives tokens on connected chain (Move VM format - 32 bytes)
        amount: 0, // Should be set explicitly in tests
        solver: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(), // Move VM address format (32 bytes)
        token_metadata: "0xcccccccccccccccccccccccccccccccccccccccc".to_string(), // Token contract address (EVM) or metadata object (Move VM)
    }
}

/// Create a base fulfillment transaction params with default test values for EVM connected chain.
/// This uses `create_base_fulfillment_transaction_params_mvm()` as a base and overrides EVM-specific fields.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let base = create_base_fulfillment_transaction_params_evm();
/// let custom = FulfillmentTransactionParams {
///     intent_id: "0xcustom".to_string(),
///     amount: 5000,
///     ..base
/// };
/// ```
#[allow(dead_code)]
pub fn create_base_fulfillment_transaction_params_evm() -> FulfillmentTransactionParams {
    FulfillmentTransactionParams {
        recipient: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(), // EVM address format (20 bytes)
        solver: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(), // EVM address format (20 bytes)
        ..create_base_fulfillment_transaction_params_mvm()
    }
}

/// Create a base Move VM transaction with default test values.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let base = create_base_mvm_transaction();
/// let custom = MvmTransaction {
///     hash: "0x123123".to_string(),
///     success: false,
///     ..base
/// };
/// ```
#[allow(dead_code)]
pub fn create_base_mvm_transaction() -> MvmTransaction {
    MvmTransaction {
        version: "12345".to_string(),
        hash: "0x123123".to_string(), // Transaction hash - arbitrary test value
        success: true,
        events: vec![],
        payload: None, // Should be set explicitly in tests
        sender: Some(
            "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(),
        ),
    }
}

/// Create a base EVM transaction with default test values.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let base = create_base_evm_transaction();
/// let custom = EvmTransaction {
///     hash: "0x123123".to_string(),
///     status: Some("0x0".to_string()), // Failed
///     ..base
/// };
/// ```
#[allow(dead_code)]
pub fn create_base_evm_transaction() -> EvmTransaction {
    EvmTransaction {
        hash: "0x123123".to_string(), // Transaction hash - arbitrary test value
        block_number: Some("0x1000".to_string()), // Block 4096 - arbitrary test value
        transaction_index: Some("0x0".to_string()),
        from: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(), // Solver who sends the transfer
        to: Some("0xcccccccccccccccccccccccccccccccccccccccc".to_string()), // Token contract address
        input: "0x".to_string(), // Should be set explicitly in tests
        value: "0x0".to_string(),
        gas: "0xfde8".to_string(), // ~65,000 gas (typical for ERC20 transfer)
        gas_price: "0x3b9aca00".to_string(), // 1 Gwei (1,000,000,000 wei) - typical test value
        status: Some("0x1".to_string()), // Success
    }
}
