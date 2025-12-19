//! Mock server setup helpers for unit tests
//!
//! This module provides helper functions for setting up mock HTTP servers
//! used in unit tests, particularly for testing solver registry interactions.

use serde_json::json;
use trusted_verifier::config::Config;
use trusted_verifier::validator::CrossChainValidator;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

// Import helpers - since both modules are declared in mod.rs, we can use the module path
#[path = "helpers.rs"]
mod helpers;
use helpers::{
    build_test_config_with_evm, build_test_config_with_mock_server, build_test_config_with_mvm,
};

// ============================================================================
// SOLVER REGISTRY RESOURCE CREATION
// ============================================================================

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

// ============================================================================
// MOCK SERVER SETUP HELPERS
// ============================================================================

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

