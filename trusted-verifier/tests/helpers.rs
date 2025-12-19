//! Shared test helpers for unit tests
//!
//! This module provides helper functions used by unit tests.

use base64::{engine::general_purpose, Engine as _};
use ed25519_dalek::SigningKey;
use rand::{Rng, RngCore};
use serde_json::json;
use trusted_verifier::config::{ApiConfig, ChainConfig, Config, EvmChainConfig, VerifierConfig};
use trusted_verifier::evm_client::EvmTransaction;
use trusted_verifier::monitor::{ChainType, EscrowEvent, FulfillmentEvent, IntentEvent};
use trusted_verifier::mvm_client::MvmTransaction;
use trusted_verifier::validator::{CrossChainValidator, FulfillmentTransactionParams};
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

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
            intent_module_address: "0x1".to_string(),
            escrow_module_address: None,
        },
        connected_chain_mvm: Some(ChainConfig {
            name: "connected".to_string(),
            rpc_url: "http://127.0.0.1:18082".to_string(),
            chain_id: 2,
            intent_module_address: "0x2".to_string(),
            escrow_module_address: Some("0x2".to_string()),
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
/// For inflow intents, offered_metadata uses {"token":"0x..."} format to match EVM escrow format.
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
        offered_metadata: r#"{"token":"0xcccccccccccccccccccccccccccccccccccccccc"}"#.to_string(), // EVM token address format for cross-chain
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

/// Create a base escrow event with default test values for Move VM connected chain.
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

/// Create a base escrow event with default test values for EVM connected chain.
/// This reflects real EVM escrow behavior where desired_metadata is always empty
/// because the EVM IntentEscrow contract doesn't store this field.
#[allow(dead_code)]
pub fn create_base_escrow_event_evm() -> EscrowEvent {
    EscrowEvent {
        escrow_id: "0x1111111111111111111111111111111111111111111111111111111111111111".to_string(), // For EVM, escrow_id = intent_id
        intent_id: "0x1111111111111111111111111111111111111111111111111111111111111111".to_string(),
        issuer: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(), // EVM address format (20 bytes)
        offered_metadata: "{\"token\":\"0xcccccccccccccccccccccccccccccccccccccccc\"}".to_string(), // Token address in JSON
        offered_amount: 1000,
        desired_metadata: "{}".to_string(), // EVM escrows don't store desired_metadata on-chain
        desired_amount: 0, // Not used for EVM inflow escrows
        expiry_time: 0,    // Should be set explicitly in tests
        revocable: false,
        reserved_solver: Some("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string()), // EVM address format (20 bytes)
        chain_id: 31337, // Matches build_test_config_with_evm
        chain_type: ChainType::Evm,
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

/// Build a test config with a mock server URL
#[allow(dead_code)]
pub fn build_test_config_with_mock_server(mock_server_url: &str) -> Config {
    let mut config = build_test_config_with_mvm();
    config.hub_chain.rpc_url = mock_server_url.to_string();
    config
}

/// Helper to create a mock SolverRegistry resource response with MVM address
/// SimpleMap<address, SolverInfo> is serialized as {"data": [{"key": address, "value": SolverInfo}, ...]}
#[allow(dead_code)]
pub fn create_solver_registry_resource_with_mvm_address(
    registry_address: &str,
    solver_address: &str,
    connected_chain_mvm_address: Option<&str>,
) -> serde_json::Value {
    let solver_entry = if let Some(mvm_addr) = connected_chain_mvm_address {
        json!({
            "key": solver_address,
            "value": {
                "public_key": [1, 2, 3, 4],
                "connected_chain_evm_address": {"vec": []},
                "connected_chain_mvm_address": {"vec": [mvm_addr]},
                "registered_at": 1234567890
            }
        })
    } else {
        json!({
            "key": solver_address,
            "value": {
                "public_key": [1, 2, 3, 4],
                "connected_chain_evm_address": {"vec": []},
                "connected_chain_mvm_address": {"vec": []},
                "registered_at": 1234567890
            }
        })
    };

    json!([{
        "type": format!("{}::solver_registry::SolverRegistry", registry_address),
        "data": {
            "solvers": {
                "data": [solver_entry]
            }
        }
    }])
}

/// Helper to create a mock SolverRegistry resource response with EVM address
/// SimpleMap<address, SolverInfo> is serialized as {"data": [{"key": address, "value": SolverInfo}, ...]}
#[allow(dead_code)]
pub fn create_solver_registry_resource_with_evm_address(
    registry_address: &str,
    solver_address: &str,
    evm_address: Option<&str>,
) -> serde_json::Value {
    let solver_entry = if let Some(evm_addr) = evm_address {
        // Convert hex string (with or without 0x) to vector<u8>
        let addr_clean = evm_addr.strip_prefix("0x").unwrap_or(evm_addr);
        let bytes: Vec<u64> = (0..addr_clean.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&addr_clean[i..i + 2], 16).unwrap() as u64)
            .collect();

        // SolverInfo with connected_chain_evm_address set
        json!({
            "key": solver_address,
            "value": {
                "public_key": [1, 2, 3, 4], // Dummy public key bytes
                "connected_chain_evm_address": {"vec": [bytes]}, // Some(vector<u8>)
                "connected_chain_mvm_address": {"vec": []}, // None
                "registered_at": 1234567890
            }
        })
    } else {
        // SolverInfo without connected_chain_evm_address
        json!({
            "key": solver_address,
            "value": {
                "public_key": [1, 2, 3, 4], // Dummy public key bytes
                "connected_chain_evm_address": {"vec": []}, // None
                "connected_chain_mvm_address": {"vec": []}, // None
                "registered_at": 1234567890
            }
        })
    };

    json!([{
        "type": format!("{}::solver_registry::SolverRegistry", registry_address),
        "data": {
            "solvers": {
                "data": [solver_entry]
            }
        }
    }])
}

/// Setup a mock server with solver registry for MVM tests
/// Returns the mock server and CrossChainValidator
#[allow(dead_code)]
pub async fn setup_mock_server_with_solver_registry(
    solver_address: Option<&str>,
    connected_chain_mvm_address: Option<&str>,
) -> (MockServer, CrossChainValidator) {
    let mock_server = MockServer::start().await;
    let registry_address = "0x1";

    if let Some(solver_addr) = solver_address {
        let resources_response = create_solver_registry_resource_with_mvm_address(
            registry_address,
            solver_addr,
            connected_chain_mvm_address,
        );

        Mock::given(method("GET"))
            .and(path(format!("/v1/accounts/{}/resources", registry_address)))
            .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
            .mount(&mock_server)
            .await;
    }

    let config = build_test_config_with_mock_server(&mock_server.uri());
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    (mock_server, validator)
}

/// Setup a mock server with solver registry for monitor tests
/// Returns the mock server and Config
#[allow(dead_code)]
pub async fn setup_mock_server_with_solver_registry_config(
    solver_address: Option<&str>,
    connected_chain_mvm_address: Option<&str>,
) -> (MockServer, Config) {
    let mock_server = MockServer::start().await;
    let registry_address = "0x1";

    if let Some(solver_addr) = solver_address {
        let resources_response = create_solver_registry_resource_with_mvm_address(
            registry_address,
            solver_addr,
            connected_chain_mvm_address,
        );

        Mock::given(method("GET"))
            .and(path(format!("/v1/accounts/{}/resources", registry_address)))
            .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
            .mount(&mock_server)
            .await;
    }

    let config = build_test_config_with_mock_server(&mock_server.uri());
    (mock_server, config)
}

/// Setup a mock server that responds to get_resources calls with SolverRegistry (MVM)
/// Returns the mock server and CrossChainValidator
#[allow(dead_code)]
pub async fn setup_mock_server_with_registry_mvm(
    registry_address: &str,
    solver_address: &str,
    connected_chain_mvm_address: Option<&str>,
) -> (MockServer, CrossChainValidator) {
    let mock_server = MockServer::start().await;

    let resources_response = create_solver_registry_resource_with_mvm_address(
        registry_address,
        solver_address,
        connected_chain_mvm_address,
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", registry_address)))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let mut config = build_test_config_with_mvm();
    config.hub_chain.rpc_url = mock_server.uri();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    (mock_server, validator)
}

/// Setup a mock server that responds to get_resources calls with SolverRegistry (EVM)
/// Returns the mock server and CrossChainValidator
#[allow(dead_code)]
pub async fn setup_mock_server_with_registry_evm(
    registry_address: &str,
    solver_address: &str,
    evm_address: Option<&str>,
) -> (MockServer, CrossChainValidator) {
    let mock_server = MockServer::start().await;

    let resources_response = create_solver_registry_resource_with_evm_address(
        registry_address,
        solver_address,
        evm_address,
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", registry_address)))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let mut config = build_test_config_with_evm();
    config.hub_chain.rpc_url = mock_server.uri();
    // Clear MVM chain config so validator uses EVM path
    config.connected_chain_mvm = None;
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    (mock_server, validator)
}

/// Setup a mock server that responds to get_solver_connected_chain_mvm_address calls
/// Returns the mock server, config, and CrossChainValidator
#[allow(dead_code)]
pub async fn setup_mock_server_with_mvm_address_response(
    solver_address: &str,
    connected_chain_mvm_address: Option<&str>,
) -> (MockServer, Config, CrossChainValidator) {
    let mock_server = MockServer::start().await;
    let registry_address = "0x1"; // Default registry address from test config

    let resources_response = create_solver_registry_resource_with_mvm_address(
        registry_address,
        solver_address,
        connected_chain_mvm_address,
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", registry_address)))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let config = build_test_config_with_mock_server(&mock_server.uri());
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    (mock_server, config, validator)
}

/// Setup a mock server that responds to get_solver_evm_address calls
/// Returns the mock server, config, and CrossChainValidator
#[allow(dead_code)]
pub async fn setup_mock_server_with_evm_address_response(
    solver_address: &str,
    evm_address: Option<&str>,
) -> (MockServer, Config, CrossChainValidator) {
    let mock_server = MockServer::start().await;
    let registry_address = "0x1"; // Default registry address from test config

    let resources_response = create_solver_registry_resource_with_evm_address(
        registry_address,
        solver_address,
        evm_address,
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", registry_address)))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let config = build_test_config_with_mock_server(&mock_server.uri());
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    (mock_server, config, validator)
}

/// Setup a mock server that returns an error response
/// Returns the mock server, config, and CrossChainValidator
#[allow(dead_code)]
pub async fn setup_mock_server_with_error(
    status_code: u16,
) -> (MockServer, Config, CrossChainValidator) {
    let mock_server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .respond_with(ResponseTemplate::new(status_code))
        .mount(&mock_server)
        .await;

    let config = build_test_config_with_mock_server(&mock_server.uri());
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    (mock_server, config, validator)
}
