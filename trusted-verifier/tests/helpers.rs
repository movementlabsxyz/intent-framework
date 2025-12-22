//! Shared test helpers for unit tests
//!
//! This module provides helper functions used by unit tests.
//!
//! The module is organized into several categories:
//! - **Configuration Builders**: Functions to create test configurations (MVM, EVM, with mock servers)
//! - **Default Event Creators**: Functions to create default test events (intents, escrows, fulfillments)
//! - **Default Transaction Creators**: Functions to create default test transactions (MVM, EVM)
//! - **Transaction Params Creators**: Functions to create fulfillment transaction parameters

use base64::{engine::general_purpose, Engine as _};
use ed25519_dalek::SigningKey;
use rand::{Rng, RngCore};
use trusted_verifier::config::{ApiConfig, ChainConfig, Config, EvmChainConfig, VerifierConfig};
use trusted_verifier::evm_client::EvmTransaction;
use trusted_verifier::monitor::{ChainType, EscrowEvent, FulfillmentEvent, IntentEvent};
use trusted_verifier::mvm_client::MvmTransaction;
use trusted_verifier::validator::FulfillmentTransactionParams;

// ============================================================================
// CONSTANTS
// ============================================================================

// --------------------------------- IDs ----------------------------------

/// Dummy intent ID (64 hex characters, valid hex format)
pub const DUMMY_INTENT_ID: &str = "0x1111111111111111111111111111111111111111111111111111111111111111";

/// Dummy escrow ID (Move VM format, 64 hex characters)
pub const DUMMY_ESCROW_ID_MVM: &str = "0x2222222222222222222222222222222222222222222222222222222222222222";

// -------------------------------- USERS ---------------------------------

/// Dummy requester address on hub chain (Move VM format, 32 bytes)
pub const DUMMY_REQUESTER_ADDR_MVM_HUB: &str = "0x3333333333333333333333333333333333333333333333333333333333333333";

/// Dummy requester address on connected chain (Move VM format, 32 bytes)
pub const DUMMY_REQUESTER_ADDR_MVM_CON: &str = "0x4444444444444444444444444444444444444444444444444444444444444444";

/// Dummy requester address (EVM format, 20 bytes)
pub const DUMMY_REQUESTER_ADDR_EVM: &str = "0x5555555555555555555555555555555555555555";

/// Dummy solver address on hub chain (Move VM format, 32 bytes)
pub const DUMMY_SOLVER_ADDR_MVM_HUB: &str = "0x6666666666666666666666666666666666666666666666666666666666666666";

/// Dummy solver address on connected chain (Move VM format, 32 bytes)
pub const DUMMY_SOLVER_ADDR_MVM_CON: &str = "0x7777777777777777777777777777777777777777777777777777777777777777";

/// Dummy solver address (EVM format, 20 bytes)
pub const DUMMY_SOLVER_ADDR_EVM: &str = "0x8888888888888888888888888888888888888888";

/// Dummy verifier address (EVM format, 20 bytes)
#[allow(dead_code)]
pub const DUMMY_VERIFIER_ADDR_EVM: &str = "0x9999999999999999999999999999999999999999";

// ------------------------- TOKENS AND CONTRACTS -------------------------

/// Dummy intent address (Move VM format, 64 hex characters)
/// This represents the Move VM object address of an intent on the hub chain
#[allow(dead_code)]
pub const DUMMY_INTENT_ADDR_MVM: &str = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

/// Dummy token address (EVM format, 20 bytes)
pub const DUMMY_TOKEN_ADDR_EVM: &str = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

/// Dummy escrow contract address (EVM format, 20 bytes)
#[allow(dead_code)]
pub const DUMMY_ESCROW_CONTRACT_ADDR_EVM: &str = "0xcccccccccccccccccccccccccccccccccccccccc";

/// Dummy metadata object address (Move VM format, 32 bytes)
#[allow(dead_code)]
pub const DUMMY_METADATA_ADDR_MVM: &str = "0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd";

// -------------------------------- OTHER ---------------------------------

/// Dummy transaction hash (64 hex characters)
#[allow(dead_code)]
pub const DUMMY_TX_HASH: &str = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";

/// Dummy timestamp for solver registration (arbitrary test value)
#[allow(dead_code)]
pub const DUMMY_REGISTERED_AT: u64 = 1234567890;

/// Dummy expiry timestamp (far future timestamp for tests)
#[allow(dead_code)]
pub const DUMMY_EXPIRY: u64 = 9999999999;

/// Dummy public key bytes used in solver registry responses
#[allow(dead_code)]
pub const DUMMY_PUBLIC_KEY: [u8; 4] = [1, 2, 3, 4];

/// Dummy solver registry address
#[allow(dead_code)]
pub const DUMMY_SOLVER_REGISTRY_ADDR: &str = "0x1";

// ============================================================================
// CONFIGURATION BUILDERS
// ============================================================================

/// Build a valid in-memory test configuration with a fresh Ed25519 keypair.
/// Keys are encoded using standard Base64 and set as environment variables.
/// The config references these env vars via private_key_env/public_key_env.
#[allow(dead_code)]
pub fn build_test_config_with_mvm() -> Config {
    let mut rng = rand::thread_rng();
    let mut sk_bytes = [0u8; 32];
    rng.fill_bytes(&mut sk_bytes);
    let signing_key = SigningKey::from_bytes(&sk_bytes);
    let verifying_key = signing_key.verifying_key();

    let private_key_b64 = general_purpose::STANDARD.encode(signing_key.to_bytes());
    let public_key_b64 = general_purpose::STANDARD.encode(verifying_key.to_bytes());

    // Use unique env var names per invocation to avoid parallel test conflicts
    let unique_id: u64 = rng.gen();
    let private_key_env_name = format!("TEST_VERIFIER_PRIVATE_KEY_{}", unique_id);
    let public_key_env_name = format!("TEST_VERIFIER_PUBLIC_KEY_{}", unique_id);

    // Set environment variables for the keys (CryptoService reads from env vars)
    std::env::set_var(&private_key_env_name, &private_key_b64);
    std::env::set_var(&public_key_env_name, &public_key_b64);

    Config {
        hub_chain: ChainConfig {
            name: "hub".to_string(),
            rpc_url: "http://127.0.0.1:18080".to_string(),
            chain_id: 1,
            intent_module_addr: "0x1".to_string(),
            escrow_module_addr: None,
        },
        connected_chain_mvm: Some(ChainConfig {
            name: "connected".to_string(),
            rpc_url: "http://127.0.0.1:18082".to_string(),
            chain_id: 2,
            intent_module_addr: "0x2".to_string(),
            escrow_module_addr: Some("0x2".to_string()),
        }),
        verifier: VerifierConfig {
            private_key_env: private_key_env_name,
            public_key_env: public_key_env_name,
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
        escrow_contract_addr: DUMMY_ESCROW_CONTRACT_ADDR_EVM.to_string(),
        chain_id: 31337,
        verifier_addr: DUMMY_VERIFIER_ADDR_EVM.to_string(),
    });
    config
}

/// Build a test config with a mock server URL
#[allow(dead_code)]
pub fn build_test_config_with_mock_server(mock_server_url: &str) -> Config {
    let mut config = build_test_config_with_mvm();
    config.hub_chain.rpc_url = mock_server_url.to_string();
    config
}

// ============================================================================
// DEFAULT EVENT CREATORS
// ============================================================================

/// Create a default intent event with test values for Move VM hub chain.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let intent = create_default_intent_mvm();
/// let custom_intent = IntentEvent {
///     desired_amount: 500,
///     expiry_time: 1000000,
///     ..intent
/// };
/// ```
#[allow(dead_code)]
pub fn create_default_intent_mvm() -> IntentEvent {
    IntentEvent {
        intent_id: DUMMY_INTENT_ID.to_string(),
        offered_metadata: "{\"inner\":\"offered_meta\"}".to_string(),
        offered_amount: 1000,
        desired_metadata: "{\"inner\":\"desired_meta\"}".to_string(),
        desired_amount: 0,
        revocable: false,
        requester_addr: DUMMY_REQUESTER_ADDR_MVM_HUB.to_string(), // Hub chain requester (Move VM format, 32 bytes)
        requester_addr_connected_chain: Some(DUMMY_REQUESTER_ADDR_MVM_CON.to_string()), // Required for outflow intents (connected_chain_id is Some). Move VM address format (32 bytes)
        reserved_solver_addr: Some(DUMMY_SOLVER_ADDR_MVM_HUB.to_string()), // Move VM address format (32 bytes)
        connected_chain_id: Some(2),
        expiry_time: 0, // Should be set explicitly in tests
        timestamp: 0,
    }
}

/// Create a default intent event with test values for EVM connected chain.
/// This uses `create_default_intent_mvm()` as a base and overrides EVM-specific fields.
/// For inflow intents, offered_metadata uses {"token":"0x..."} format to match EVM escrow format.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let intent = create_default_intent_evm();
/// let custom_intent = IntentEvent {
///     desired_amount: 500,
///     expiry_time: 1000000,
///     ..intent
/// };
/// ```
#[allow(dead_code)]
pub fn create_default_intent_evm() -> IntentEvent {
    IntentEvent {
        offered_metadata: format!(r#"{{"token":"{}"}}"#, DUMMY_TOKEN_ADDR_EVM), // EVM token address format for cross-chain
        connected_chain_id: Some(31337), // EVM chain ID (matches build_test_config_with_evm)
        requester_addr_connected_chain: Some(DUMMY_REQUESTER_ADDR_EVM.to_string()), // EVM address format (20 bytes)
        ..create_default_intent_mvm()
    }
}

/// Create a default fulfillment event with test values.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let fulfillment = create_default_fulfillment();
/// let custom_fulfillment = FulfillmentEvent {
///     timestamp: 1000000,
///     provided_amount: 500,
///     provided_metadata: "{\"token\":\"USDC\"}".to_string(),
///     ..fulfillment
/// };
/// ```
#[allow(dead_code)]
pub fn create_default_fulfillment() -> FulfillmentEvent {
    FulfillmentEvent {
        intent_id: DUMMY_INTENT_ID.to_string(),
        intent_addr: DUMMY_INTENT_ADDR_MVM.to_string(),
        solver_addr: DUMMY_SOLVER_ADDR_MVM_CON.to_string(),
        provided_metadata: "{}".to_string(),
        provided_amount: 0,
        timestamp: 0, // Should be set explicitly in tests
    }
}

/// Create a default escrow event with test values for Move VM connected chain.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let escrow = create_default_escrow_event();
/// let custom_escrow = EscrowEvent {
///     escrow_id: "0xescrow_id".to_string(),
///     intent_id: "0xintent_id".to_string(),
///     offered_amount: 1000,
///     ..escrow
/// };
/// ```
#[allow(dead_code)]
pub fn create_default_escrow_event() -> EscrowEvent {
    EscrowEvent {
        escrow_id: DUMMY_ESCROW_ID_MVM.to_string(),
        intent_id: DUMMY_INTENT_ID.to_string(),
        offered_metadata: "{\"inner\":\"offered_meta\"}".to_string(),
        offered_amount: 1000,
        desired_metadata: "{\"inner\":\"desired_meta\"}".to_string(),
        desired_amount: 0, // Escrow desired_amount must be 0 (validation requirement)
        revocable: false,
        requester_addr: DUMMY_REQUESTER_ADDR_MVM_CON.to_string(), // EscrowEvent.requester_addr is the requester who created the escrow and locked funds (for inflow escrows on connected chain)
        reserved_solver_addr: Some(DUMMY_SOLVER_ADDR_MVM_HUB.to_string()),
        chain_id: 2,
        chain_type: ChainType::Mvm,
        expiry_time: 0,    // Should be set explicitly in tests
        timestamp: 0, // Should be set explicitly in tests
    }
}

/// Create a default escrow event with test values for EVM connected chain.
/// This reflects real EVM escrow behavior where desired_metadata is always empty
/// because the EVM IntentEscrow contract doesn't store this field.
#[allow(dead_code)]
pub fn create_default_escrow_event_evm() -> EscrowEvent {
    EscrowEvent {
        escrow_id: DUMMY_INTENT_ID.to_string(), // For EVM, escrow_id = intent_id
        intent_id: DUMMY_INTENT_ID.to_string(),
        offered_metadata: format!("{{\"token\":\"{}\"}}", DUMMY_TOKEN_ADDR_EVM), // Token address in JSON
        offered_amount: 1000,
        desired_metadata: "{}".to_string(), // EVM escrows don't store desired_metadata on-chain
        desired_amount: 0, // Not used for EVM inflow escrows
        revocable: false,
        requester_addr: DUMMY_REQUESTER_ADDR_EVM.to_string(), // EVM address format (20 bytes)
        reserved_solver_addr: Some(DUMMY_SOLVER_ADDR_EVM.to_string()), // EVM address format (20 bytes)
        chain_id: 31337, // Matches build_test_config_with_evm
        chain_type: ChainType::Evm,
        expiry_time: 0,    // Should be set explicitly in tests
        timestamp: 0, // Should be set explicitly in tests
    }
}

/// Create a default fulfillment transaction params with test values for Move VM connected chain.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let default = create_default_fulfillment_transaction_params_mvm();
/// let custom = FulfillmentTransactionParams {
///     intent_id: "0xcustom".to_string(),
///     amount: 5000,
///     ..default
/// };
/// ```
#[allow(dead_code)]
pub fn create_default_fulfillment_transaction_params_mvm() -> FulfillmentTransactionParams {
    FulfillmentTransactionParams {
        intent_id: DUMMY_INTENT_ID.to_string(),
        recipient_addr: DUMMY_REQUESTER_ADDR_MVM_CON.to_string(), // Requester who receives tokens on connected chain (Move VM format - 32 bytes)
        amount: 0, // Should be set explicitly in tests
        solver_addr: DUMMY_SOLVER_ADDR_MVM_CON.to_string(), // Move VM address format (32 bytes)
        token_metadata: DUMMY_TOKEN_ADDR_EVM.to_string(), // Token contract address (EVM) or metadata object (Move VM)
    }
}

/// Create a default fulfillment transaction params with test values for EVM connected chain.
/// This uses `create_default_fulfillment_transaction_params_mvm()` as a base and overrides EVM-specific fields.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let default = create_default_fulfillment_transaction_params_evm();
/// let custom = FulfillmentTransactionParams {
///     intent_id: "0xcustom".to_string(),
///     amount: 5000,
///     ..default
/// };
/// ```
#[allow(dead_code)]
pub fn create_default_fulfillment_transaction_params_evm() -> FulfillmentTransactionParams {
    FulfillmentTransactionParams {
        recipient_addr: DUMMY_REQUESTER_ADDR_EVM.to_string(), // EVM address format (20 bytes)
        solver_addr: DUMMY_SOLVER_ADDR_EVM.to_string(), // EVM address format (20 bytes)
        ..create_default_fulfillment_transaction_params_mvm()
    }
}

/// Create a default Move VM transaction with test values.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let default = create_default_mvm_transaction();
/// let custom = MvmTransaction {
///     hash: "0x123123".to_string(),
///     success: false,
///     ..default
/// };
/// ```
#[allow(dead_code)]
pub fn create_default_mvm_transaction() -> MvmTransaction {
    MvmTransaction {
        version: "12345".to_string(),
        hash: "0x123123".to_string(), // Transaction hash - arbitrary test value
        success: true,
        events: vec![],
        payload: None, // Should be set explicitly in tests
        sender: Some(DUMMY_SOLVER_ADDR_MVM_CON.to_string()),
    }
}

/// Create a default EVM transaction with test values.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let default = create_default_evm_transaction();
/// let custom = EvmTransaction {
///     hash: "0x123123".to_string(),
///     status: Some("0x0".to_string()), // Failed
///     ..default
/// };
/// ```
#[allow(dead_code)]
pub fn create_default_evm_transaction() -> EvmTransaction {
    EvmTransaction {
        hash: "0x123123".to_string(), // Transaction hash - arbitrary test value
        block_number: Some("0x1000".to_string()), // Block 4096 - arbitrary test value
        transaction_index: Some("0x0".to_string()),
        from: DUMMY_SOLVER_ADDR_EVM.to_string(), // Solver who sends the transfer
        to: Some(DUMMY_TOKEN_ADDR_EVM.to_string()), // Token contract address
        input: "0x".to_string(), // Should be set explicitly in tests
        value: "0x0".to_string(),
        gas: "0xfde8".to_string(), // ~65,000 gas (typical for ERC20 transfer)
        gas_price: "0x3b9aca00".to_string(), // 1 Gwei (1,000,000,000 wei) - typical test value
        status: Some("0x1".to_string()), // Success
    }
}
