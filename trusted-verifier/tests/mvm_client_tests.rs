//! Unit tests for MVM client functions
//!
//! These tests verify that MVM client functions work correctly,
//! including resource queries and registry lookups.

use trusted_verifier::mvm_client::MvmClient;
use wiremock::{MockServer, Mock, ResponseTemplate};
use wiremock::matchers::{method, path};
use serde_json::json;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a mock SolverRegistry resource response
/// SimpleMap<address, SolverInfo> is serialized as {"data": [{"key": address, "value": SolverInfo}, ...]}
fn create_solver_registry_resource(
    registry_address: &str,
    solver_address: &str,
    connected_chain_mvm_address: Option<&str>,
) -> serde_json::Value {
    let solver_entry = if let Some(mvm_addr) = connected_chain_mvm_address {
        // SolverInfo with connected_chain_mvm_address set
        json!({
            "key": solver_address,
            "value": {
                "public_key": [1, 2, 3, 4], // Dummy public key bytes
                "connected_chain_evm_address": {"vec": []}, // None
                "connected_chain_mvm_address": {"vec": [mvm_addr]}, // Some(address)
                "registered_at": 1234567890
            }
        })
    } else {
        // SolverInfo without connected_chain_mvm_address
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

/// Setup a mock server that responds to get_resources calls with SolverRegistry
async fn setup_mock_server_with_registry(
    registry_address: &str,
    solver_address: &str,
    connected_chain_mvm_address: Option<&str>,
) -> (MockServer, MvmClient) {
    let mock_server = MockServer::start().await;
    
    let resources_response = create_solver_registry_resource(
        registry_address,
        solver_address,
        connected_chain_mvm_address,
    );
    
    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", registry_address)))
        .respond_with(ResponseTemplate::new(200)
            .set_body_json(resources_response))
        .mount(&mock_server)
        .await;
    
    let client = MvmClient::new(&mock_server.uri())
        .expect("Failed to create MvmClient");
    
    (mock_server, client)
}

// ============================================================================
// TESTS
// ============================================================================

/// Test that get_solver_connected_chain_mvm_address returns the address when solver is registered
/// Why: Verify successful lookup when solver has a connected chain MVM address
#[tokio::test]
async fn test_get_solver_connected_chain_mvm_address_success() {
    let registry_address = "0x1";
    let solver_address = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let connected_chain_mvm_address = "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
    
    let (_mock_server, client) = setup_mock_server_with_registry(
        registry_address,
        solver_address,
        Some(connected_chain_mvm_address),
    ).await;
    
    let result = client.get_solver_connected_chain_mvm_address(
        solver_address,
        registry_address,
    ).await;
    
    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(address, Some(connected_chain_mvm_address.to_string()),
               "Should return the connected chain MVM address");
}

/// Test that get_solver_connected_chain_mvm_address returns None when solver has no connected chain address
/// Why: Verify correct handling when solver is registered but has no connected chain MVM address
#[tokio::test]
async fn test_get_solver_connected_chain_mvm_address_none() {
    let registry_address = "0x1";
    let solver_address = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    
    let (_mock_server, client) = setup_mock_server_with_registry(
        registry_address,
        solver_address,
        None, // No connected chain MVM address
    ).await;
    
    let result = client.get_solver_connected_chain_mvm_address(
        solver_address,
        registry_address,
    ).await;
    
    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(address, None, "Should return None when no connected chain MVM address is set");
}

/// Test that get_solver_connected_chain_mvm_address returns None when solver is not registered
/// Why: Verify correct handling when solver is not in the registry
#[tokio::test]
async fn test_get_solver_connected_chain_mvm_address_solver_not_found() {
    let registry_address = "0x1";
    let registered_solver = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    let unregistered_solver = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    
    let (_mock_server, client) = setup_mock_server_with_registry(
        registry_address,
        registered_solver, // Only this solver is registered
        Some("0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
    ).await;
    
    let result = client.get_solver_connected_chain_mvm_address(
        unregistered_solver, // Query for unregistered solver
        registry_address,
    ).await;
    
    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(address, None, "Should return None when solver is not registered");
}

/// Test that get_solver_connected_chain_mvm_address returns None when registry resource is not found
/// Why: Verify correct handling when SolverRegistry resource doesn't exist
#[tokio::test]
async fn test_get_solver_connected_chain_mvm_address_registry_not_found() {
    let mock_server = MockServer::start().await;
    let registry_address = "0x1";
    let solver_address = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    
    // Mock empty resources (no SolverRegistry)
    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", registry_address)))
        .respond_with(ResponseTemplate::new(200)
            .set_body_json(json!([]))) // Empty resources
        .mount(&mock_server)
        .await;
    
    let client = MvmClient::new(&mock_server.uri())
        .expect("Failed to create MvmClient");
    
    let result = client.get_solver_connected_chain_mvm_address(
        solver_address,
        registry_address,
    ).await;
    
    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(address, None, "Should return None when registry resource is not found");
}

/// Test that get_solver_connected_chain_mvm_address handles address normalization (with/without 0x prefix)
/// Why: Verify that address matching works regardless of 0x prefix
#[tokio::test]
async fn test_get_solver_connected_chain_mvm_address_address_normalization() {
    let registry_address = "0x1";
    let solver_address_with_prefix = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let solver_address_without_prefix = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let connected_chain_mvm_address = "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
    
    let (_mock_server, client) = setup_mock_server_with_registry(
        registry_address,
        solver_address_with_prefix, // Registry has address with 0x prefix
        Some(connected_chain_mvm_address),
    ).await;
    
    // Query with address without 0x prefix
    let result = client.get_solver_connected_chain_mvm_address(
        solver_address_without_prefix,
        registry_address,
    ).await;
    
    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(address, Some(connected_chain_mvm_address.to_string()),
               "Should return the connected chain MVM address regardless of 0x prefix");
}

