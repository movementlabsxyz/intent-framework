//! Mock server setup helpers for unit tests
//!
//! This module provides helper functions for setting up mock HTTP servers
//! used in unit tests, particularly for testing solver registry interactions.
//!
//! The module is organized into two sections:
//! - **Solver Registry Resource Creation**: Functions to create mock SolverRegistry JSON responses
//! - **Mock Server Setup Helpers**: Functions to set up WireMock servers with various configurations

use serde_json::json;
use trusted_verifier::config::Config;
use trusted_verifier::validator::CrossChainValidator;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

#[path = "helpers.rs"]
mod helpers;
use helpers::{
    build_test_config_with_evm, build_test_config_with_mock_server, build_test_config_with_mvm,
    DUMMY_PUBLIC_KEY, DUMMY_REGISTERED_AT, DUMMY_SOLVER_REGISTRY_ADDR,
};

// ============================================================================
// SOLVER REGISTRY RESOURCE CREATION
// ============================================================================

/// Helper to create a mock SolverRegistry resource response with MVM address
/// SimpleMap<address, SolverInfo> is serialized as {"data": [{"key": address, "value": SolverInfo}, ...]}
#[allow(dead_code)]
pub fn create_solver_registry_resource_with_mvm_address(
    solver_registry_addr: &str,
    solver_addr: &str,
    solver_connected_chain_mvm_addr: Option<&str>,
) -> serde_json::Value {
    let solver_entry = if let Some(mvm_addr) = solver_connected_chain_mvm_addr {
        json!({
            "key": solver_addr,
            "value": {
                "public_key": DUMMY_PUBLIC_KEY,
                "connected_chain_evm_addr": {"vec": []},
                "connected_chain_mvm_addr": {"vec": [mvm_addr]},
                "registered_at": DUMMY_REGISTERED_AT
            }
        })
    } else {
        json!({
            "key": solver_addr,
            "value": {
                "public_key": DUMMY_PUBLIC_KEY,
                "connected_chain_evm_addr": {"vec": []},
                "connected_chain_mvm_addr": {"vec": []},
                "registered_at": DUMMY_REGISTERED_AT
            }
        })
    };

    json!([{
        "type": format!("{}::solver_registry::SolverRegistry", solver_registry_addr),
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
    solver_registry_addr: &str,
    solver_addr: &str,
    solver_connected_chain_evm_addr: Option<&str>,
) -> serde_json::Value {
    let solver_entry = if let Some(evm_addr) = solver_connected_chain_evm_addr {
        // Convert hex string (with or without 0x) to vector<u8>
        let addr_clean = evm_addr.strip_prefix("0x").unwrap_or(evm_addr);
        let bytes: Vec<u64> = (0..addr_clean.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&addr_clean[i..i + 2], 16).unwrap() as u64)
            .collect();

        // SolverInfo with connected_chain_evm_addr set
        json!({
            "key": solver_addr,
            "value": {
                "public_key": DUMMY_PUBLIC_KEY,
                "connected_chain_evm_addr": {"vec": [bytes]}, // Some(vector<u8>)
                "connected_chain_mvm_addr": {"vec": []}, // None
                "registered_at": DUMMY_REGISTERED_AT
            }
        })
    } else {
        // SolverInfo without connected_chain_evm_addr
        json!({
            "key": solver_addr,
            "value": {
                "public_key": DUMMY_PUBLIC_KEY,
                "connected_chain_evm_addr": {"vec": []}, // None
                "connected_chain_mvm_addr": {"vec": []}, // None
                "registered_at": DUMMY_REGISTERED_AT
            }
        })
    };

    json!([{
        "type": format!("{}::solver_registry::SolverRegistry", solver_registry_addr),
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
    solver_addr: Option<&str>,
    solver_connected_chain_mvm_addr: Option<&str>,
) -> (MockServer, CrossChainValidator) {
    let mock_server = MockServer::start().await;
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;

    // Extract solver_addr from Option: if Some, set up mock response; if None, skip mock setup
    // Note: Inside this block, solver_addr shadows the parameter and refers to the extracted &str
    if let Some(solver_addr) = solver_addr {
        let resources_response = create_solver_registry_resource_with_mvm_address(
            solver_registry_addr,
            solver_addr,
            solver_connected_chain_mvm_addr,
        );

        Mock::given(method("GET"))
            .and(path(format!("/v1/accounts/{}/resources", solver_registry_addr)))
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
    solver_addr: Option<&str>,
    solver_connected_chain_mvm_addr: Option<&str>,
) -> (MockServer, Config) {
    let mock_server = MockServer::start().await;
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;

    // Extract solver_addr from Option: if Some, set up mock response; if None, skip mock setup
    // Note: Inside this block, solver_addr shadows the parameter and refers to the extracted &str
    if let Some(solver_addr) = solver_addr {
        let resources_response = create_solver_registry_resource_with_mvm_address(
            solver_registry_addr,
            solver_addr,
            solver_connected_chain_mvm_addr,
        );

        Mock::given(method("GET"))
            .and(path(format!("/v1/accounts/{}/resources", solver_registry_addr)))
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
    solver_registry_addr: &str,
    solver_addr: &str,
    solver_connected_chain_mvm_addr: Option<&str>,
) -> (MockServer, CrossChainValidator) {
    let mock_server = MockServer::start().await;

    let resources_response = create_solver_registry_resource_with_mvm_address(
        solver_registry_addr,
        solver_addr,
        solver_connected_chain_mvm_addr,
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", solver_registry_addr)))
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
    solver_registry_addr: &str,
    solver_addr: &str,
    solver_connected_chain_evm_addr: Option<&str>,
) -> (MockServer, CrossChainValidator) {
    let mock_server = MockServer::start().await;

    let resources_response = create_solver_registry_resource_with_evm_address(
        solver_registry_addr,
        solver_addr,
        solver_connected_chain_evm_addr,
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", solver_registry_addr)))
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

/// Setup a mock server that responds to get_solver_connected_chain_mvm_addr calls
/// Returns the mock server, config, and CrossChainValidator
#[allow(dead_code)]
pub async fn setup_mock_server_with_mvm_address_response(
    solver_addr: &str,
    solver_connected_chain_mvm_addr: Option<&str>,
) -> (MockServer, Config, CrossChainValidator) {
    let mock_server = MockServer::start().await;
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;

    let resources_response = create_solver_registry_resource_with_mvm_address(
        solver_registry_addr,
        solver_addr,
        solver_connected_chain_mvm_addr,
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", solver_registry_addr)))
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
    solver_addr: &str,
    solver_connected_chain_evm_addr: Option<&str>,
) -> (MockServer, Config, CrossChainValidator) {
    let mock_server = MockServer::start().await;
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;

    let resources_response = create_solver_registry_resource_with_evm_address(
        solver_registry_addr,
        solver_addr,
        solver_connected_chain_evm_addr,
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", solver_registry_addr)))
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

