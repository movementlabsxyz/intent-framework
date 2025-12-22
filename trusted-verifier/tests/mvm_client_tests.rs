//! Unit tests for MVM client functions
//!
//! These tests verify that MVM client functions work correctly,
//! including resource queries and registry lookups.

use serde_json::json;
use trusted_verifier::mvm_client::MvmClient;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

#[path = "mod.rs"]
mod test_helpers;
use test_helpers::{
    DUMMY_PUBLIC_KEY, DUMMY_REGISTERED_AT, DUMMY_SOLVER_ADDR_EVM,
    DUMMY_SOLVER_ADDR_MVM_HUB, DUMMY_SOLVER_ADDR_MVM_CON, DUMMY_SOLVER_REGISTRY_ADDR,
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a mock SolverRegistry resource response
/// SimpleMap<address, SolverInfo> is serialized as {"data": [{"key": address, "value": SolverInfo}, ...]}
fn create_solver_registry_resource(
    solver_registry_addr: &str,
    solver_addr: &str,
    solver_connected_chain_mvm_addr: Option<&str>,
) -> serde_json::Value {
    let solver_entry = if let Some(mvm_addr) = solver_connected_chain_mvm_addr {
        // SolverInfo with connected_chain_mvm_addr set
        json!({
            "key": solver_addr,
            "value": {
                "public_key": DUMMY_PUBLIC_KEY,
                "connected_chain_evm_addr": {"vec": []}, // None
                "connected_chain_mvm_addr": {"vec": [mvm_addr]}, // Some(address)
                "registered_at": DUMMY_REGISTERED_AT
            }
        })
    } else {
        // SolverInfo without connected_chain_mvm_addr
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

/// Setup a mock server that responds to get_resources calls with SolverRegistry
async fn setup_mock_server_with_registry(
    solver_registry_addr: &str,
    solver_addr: &str,
    solver_connected_chain_mvm_addr: Option<&str>,
) -> (MockServer, MvmClient) {
    let mock_server = MockServer::start().await;

    let resources_response = create_solver_registry_resource(
        solver_registry_addr,
        solver_addr,
        solver_connected_chain_mvm_addr,
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", solver_registry_addr)))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    (mock_server, client)
}

// ============================================================================
// TESTS
// ============================================================================

/// Test that get_solver_connected_chain_mvm_addr returns the address when solver is registered
/// Why: Verify successful lookup when solver has a connected chain MVM address
#[tokio::test]
async fn test_get_solver_connected_chain_mvm_addr_success() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;
    let solver_connected_chain_mvm_addr =
        DUMMY_SOLVER_ADDR_MVM_CON;

    let (_mock_server, client) = setup_mock_server_with_registry(
        solver_registry_addr,
        solver_addr,
        Some(solver_connected_chain_mvm_addr),
    )
    .await;

    let result = client
        .get_solver_connected_chain_mvm_address(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address,
        Some(solver_connected_chain_mvm_addr.to_string()),
        "Should return the connected chain MVM address"
    );
}

/// Test that get_solver_connected_chain_mvm_addr returns None when solver has no connected chain address
/// Why: Verify correct handling when solver is registered but has no connected chain MVM address
#[tokio::test]
async fn test_get_solver_connected_chain_mvm_addr_none() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;

    let (_mock_server, client) = setup_mock_server_with_registry(
        solver_registry_addr,
        solver_addr,
        None, // No connected chain MVM address
    )
    .await;

    let result = client
        .get_solver_connected_chain_mvm_address(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address, None,
        "Should return None when no connected chain MVM address is set"
    );
}

/// Test that get_solver_connected_chain_mvm_addr returns None when solver is not registered
/// Why: Verify correct handling when solver is not in the registry
#[tokio::test]
async fn test_get_solver_connected_chain_mvm_addr_solver_not_found() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let registered_solver = DUMMY_SOLVER_ADDR_MVM_HUB;
    let unregistered_solver = "0xunregistered_solver_addr"; // Unregistered solver address for testing

    let (_mock_server, client) = setup_mock_server_with_registry(
        solver_registry_addr,
        registered_solver, // Only this solver is registered
        Some(DUMMY_SOLVER_ADDR_MVM_CON),
    )
    .await;

    let result = client
        .get_solver_connected_chain_mvm_address(
            unregistered_solver, // Query for unregistered solver
            solver_registry_addr,
        )
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address, None,
        "Should return None when solver is not registered"
    );
}

/// Test that get_solver_connected_chain_mvm_addr returns None when registry resource is not found
/// Why: Verify correct handling when SolverRegistry resource doesn't exist
#[tokio::test]
async fn test_get_solver_connected_chain_mvm_addr_registry_not_found() {
    let mock_server = MockServer::start().await;
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;

    // Mock empty resources (no SolverRegistry)
    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", solver_registry_addr)))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!([]))) // Empty resources
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_connected_chain_mvm_address(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address, None,
        "Should return None when registry resource is not found"
    );
}

/// Test that get_solver_connected_chain_mvm_addr handles address normalization (with/without 0x prefix)
/// Why: Verify that address matching works regardless of 0x prefix
#[tokio::test]
async fn test_get_solver_connected_chain_mvm_addr_address_normalization() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr_with_prefix = DUMMY_SOLVER_ADDR_MVM_HUB;
    let solver_addr_without_prefix = &DUMMY_SOLVER_ADDR_MVM_HUB[2..]; // Remove 0x prefix
    let solver_connected_chain_mvm_addr =
        DUMMY_SOLVER_ADDR_MVM_CON;

    let (_mock_server, client) = setup_mock_server_with_registry(
        solver_registry_addr,
        solver_addr_with_prefix, // Registry has address with 0x prefix
        Some(solver_connected_chain_mvm_addr),
    )
    .await;

    // Query with address without 0x prefix
    let result = client
        .get_solver_connected_chain_mvm_address(solver_addr_without_prefix, solver_registry_addr)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address,
        Some(solver_connected_chain_mvm_addr.to_string()),
        "Should return the connected chain MVM address regardless of 0x prefix"
    );
}

/// Create a mock SolverRegistry resource response with EVM address in hex string format
/// This tests the case where Aptos serializes Option<vector<u8>> as {"vec": ["0xhexstring"]}
/// instead of {"vec": [[bytes_array]]}
fn create_solver_registry_resource_with_evm_address_hex_string(
    solver_registry_addr: &str,
    solver_addr: &str,
    solver_connected_chain_evm_addr: Option<&str>,
) -> serde_json::Value {
    let solver_entry = if let Some(evm_addr) = solver_connected_chain_evm_addr {
        // SolverInfo with connected_chain_evm_addr set as hex string (Aptos serialization format)
        json!({
            "key": solver_addr,
            "value": {
                "public_key": DUMMY_PUBLIC_KEY,
                "connected_chain_evm_addr": {"vec": [evm_addr]}, // Some(vector<u8>) as hex string
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

/// Create a mock SolverRegistry resource response with EVM address in array format
/// This tests the case where Aptos serializes Option<vector<u8>> as {"vec": [[bytes_array]]}
fn create_solver_registry_resource_with_evm_address_array(
    solver_registry_addr: &str,
    solver_addr: &str,
    solver_connected_chain_evm_addr: Option<&str>,
) -> serde_json::Value {
    let solver_entry = if let Some(evm_addr) = solver_connected_chain_evm_addr {
        // Convert hex string (with or without 0x) to vector<u8> as array
        let addr_clean = evm_addr.strip_prefix("0x").unwrap_or(evm_addr);
        let bytes: Vec<u64> = (0..addr_clean.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&addr_clean[i..i + 2], 16).unwrap() as u64)
            .collect();

        // SolverInfo with connected_chain_evm_addr set as byte array
        json!({
            "key": solver_addr,
            "value": {
                "public_key": DUMMY_PUBLIC_KEY,
                "connected_chain_evm_addr": {"vec": [bytes]}, // Some(vector<u8>) as array
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

/// Test that get_solver_evm_address handles array format from Aptos
/// Why: Aptos can serialize Option<vector<u8>> as {"vec": [[bytes_array]]}
/// This test verifies we correctly parse the array format
#[tokio::test]
async fn test_get_solver_evm_address_array_format() {
    let mock_server = MockServer::start().await;
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;
    let solver_connected_chain_evm_addr = DUMMY_SOLVER_ADDR_EVM; // Solver's EVM address on connected chain

    let resources_response = create_solver_registry_resource_with_evm_address_array(
        solver_registry_addr,
        solver_addr,
        Some(solver_connected_chain_evm_addr),
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", solver_registry_addr)))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_evm_address(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address,
        Some(solver_connected_chain_evm_addr.to_string()),
        "Should return the EVM address when serialized as array format"
    );
}

/// Test that get_solver_evm_address handles hex string format from Aptos
/// Why: Aptos can serialize Option<vector<u8>> as {"vec": ["0xhexstring"]} instead of {"vec": [[bytes]]}
/// This test verifies we correctly parse the hex string format (the format that caused EVM outflow validation failures)
#[tokio::test]
async fn test_get_solver_evm_address_hex_string_format() {
    let mock_server = MockServer::start().await;
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;
    let solver_connected_chain_evm_addr = DUMMY_SOLVER_ADDR_EVM; // Solver's EVM address on connected chain

    let resources_response = create_solver_registry_resource_with_evm_address_hex_string(
        solver_registry_addr,
        solver_addr,
        Some(solver_connected_chain_evm_addr),
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", solver_registry_addr)))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_evm_address(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address,
        Some(solver_connected_chain_evm_addr.to_string()),
        "Should return the EVM address when serialized as hex string format"
    );
}

// ============================================================================
// LEADING ZERO TESTS
// ============================================================================

/// Create a mock SolverRegistry resource where the type name has leading zeros stripped
/// This simulates Move's behavior of stripping leading zeros from addresses in type names
/// Example: 0x0a4c... becomes 0xa4c... in the resource type
fn create_solver_registry_resource_with_stripped_zeros(
    solver_registry_addr_in_type: &str,
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
        "type": format!("{}::solver_registry::SolverRegistry", solver_registry_addr_in_type),
        "data": {
            "solvers": {
                "data": [solver_entry]
            }
        }
    }])
}

/// Test that get_solver_connected_chain_mvm_addr handles leading zero mismatch
/// Why: Move strips leading zeros from addresses in type names (e.g., 0x0a4c... becomes 0xa4c...)
///      but the registry address passed to the function may have leading zeros.
#[tokio::test]
async fn test_get_solver_mvm_address_leading_zero_mismatch() {
    let mock_server = MockServer::start().await;

    // Solver registry address with leading zero after 0x prefix
    let solver_registry_addr_full = "0x0123456789012345678901234567890123456789012345678901234567890123";
    // Same address but Move strips the leading zero in type names
    let solver_registry_addr_stripped = "0x123456789012345678901234567890123456789012345678901234567890123";
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;
    let solver_connected_chain_mvm_addr =
        DUMMY_SOLVER_ADDR_MVM_CON;

    // Mock response has the type with stripped leading zero (like Move does)
    let resources_response = create_solver_registry_resource_with_stripped_zeros(
        solver_registry_addr_stripped,
        solver_addr,
        Some(solver_connected_chain_mvm_addr),
    );

    // But the API endpoint uses the full address
    Mock::given(method("GET"))
        .and(path(format!(
            "/v1/accounts/{}/resources",
            solver_registry_addr_full
        )))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    // Query with the full address (with leading zero)
    let result = client
        .get_solver_connected_chain_mvm_address(solver_addr, solver_registry_addr_full)
        .await;

    assert!(
        result.is_ok(),
        "Query should succeed despite leading zero mismatch"
    );
    let address = result.unwrap();
    assert_eq!(
        address,
        Some(solver_connected_chain_mvm_addr.to_string()),
        "Should find the SolverRegistry despite leading zero being stripped in type name"
    );
}

/// Test that get_solver_evm_address handles leading zero mismatch
/// Why: Same as above, but for EVM address lookup
#[tokio::test]
async fn test_get_solver_evm_address_leading_zero_mismatch() {
    let mock_server = MockServer::start().await;

    // Solver registry address with leading zero
    let solver_registry_addr_full = "0x0123456789012345678901234567890123456789012345678901234567890123";
    // Move strips the leading zero in type names
    let solver_registry_addr_stripped = "0x123456789012345678901234567890123456789012345678901234567890123";
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;
    let solver_connected_chain_evm_addr = DUMMY_SOLVER_ADDR_EVM;

    // Create mock response with stripped leading zero in type name
    // Use hex string format (like Aptos serializes Option<vector<u8>>)
    let solver_entry = json!({
        "key": solver_addr,
        "value": {
            "public_key": DUMMY_PUBLIC_KEY,
            "connected_chain_evm_addr": {"vec": [solver_connected_chain_evm_addr]},
            "connected_chain_mvm_addr": {"vec": []},
            "registered_at": DUMMY_REGISTERED_AT
        }
    });

    let resources_response = json!([{
        "type": format!("{}::solver_registry::SolverRegistry", solver_registry_addr_stripped),
        "data": {
            "solvers": {
                "data": [solver_entry]
            }
        }
    }]);

    Mock::given(method("GET"))
        .and(path(format!(
            "/v1/accounts/{}/resources",
            solver_registry_addr_full
        )))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    // Query with the full address (with leading zero)
    let result = client
        .get_solver_evm_address(solver_addr, solver_registry_addr_full)
        .await;

    assert!(
        result.is_ok(),
        "Query should succeed despite leading zero mismatch"
    );
    let address = result.unwrap();
    assert_eq!(
        address,
        Some(solver_connected_chain_evm_addr.to_string()),
        "Should find the SolverRegistry despite leading zero being stripped in type name"
    );
}

// ============================================================================
// GET_SOLVER_PUBLIC_KEY TESTS
// ============================================================================

/// Setup a mock server that responds to get_public_key view function calls
async fn setup_mock_server_with_public_key(
    _solver_registry_addr: &str,
    _solver_addr: &str,
    public_key: Option<&[u8]>,
) -> (MockServer, MvmClient) {
    let mock_server = MockServer::start().await;

    // Aptos view function returns array of return values
    // For get_public_key returning vector<u8>, response is ["0x..."] (hex string)
    let view_response: Vec<serde_json::Value> = if let Some(pk) = public_key {
        // Return public key as hex string in an array (Aptos API format)
        vec![json!(format!("0x{}", hex::encode(pk)))]
    } else {
        // Return empty hex string (solver not registered)
        vec![json!("0x")]
    };

    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .respond_with(ResponseTemplate::new(200).set_body_json(view_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    (mock_server, client)
}

/// Test that get_solver_public_key returns public key when solver is registered
/// What is tested: Successful retrieval of solver public key from registry
/// Why: Signature submission requires verifying solver is registered
#[tokio::test]
async fn test_get_solver_public_key_success() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;
    let public_key = vec![1u8, 2u8, 3u8, 4u8, 5u8]; // Test public key

    let (_mock_server, client) = setup_mock_server_with_public_key(
        solver_registry_addr,
        solver_addr,
        Some(&public_key),
    )
    .await;

    let result = client
        .get_solver_public_key(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let pk = result.unwrap();
    assert_eq!(pk, Some(public_key), "Should return the public key");
}

/// Test that get_solver_public_key returns None when solver is not registered
/// What is tested: Handling of unregistered solver
/// Why: Unregistered solvers should be rejected
#[tokio::test]
async fn test_get_solver_public_key_not_registered() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;

    let (_mock_server, client) = setup_mock_server_with_public_key(
        solver_registry_addr,
        solver_addr,
        None, // No public key = not registered
    )
    .await;

    let result = client
        .get_solver_public_key(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let pk = result.unwrap();
    assert_eq!(pk, None, "Should return None for unregistered solver");
}

/// Test that get_solver_public_key handles empty hex string (not registered)
/// What is tested: Empty hex string means solver is not registered
/// Why: Aptos returns "0x" for empty vector<u8>
#[tokio::test]
async fn test_get_solver_public_key_empty_hex_string() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;

    // Empty hex string response (Aptos API format for empty vector<u8>)
    let mock_server = MockServer::start().await;
    let view_response = json!(["0x"]);

    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .respond_with(ResponseTemplate::new(200).set_body_json(view_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_public_key(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let pk = result.unwrap();
    assert_eq!(pk, None, "Should return None for empty hex string");
}

/// Test that get_solver_public_key errors on unexpected response format
/// What is tested: Unexpected response format results in error
/// Why: We should fail loudly on unexpected formats, not silently return None
#[tokio::test]
async fn test_get_solver_public_key_errors_on_unexpected_format() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;

    let mock_server = MockServer::start().await;
    // Return an object instead of array - this is unexpected
    let view_response = json!({"unexpected": "format"});

    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .respond_with(ResponseTemplate::new(200).set_body_json(view_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_public_key(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_err(), "Should error on unexpected format");
    let err = result.unwrap_err();
    assert!(
        err.to_string().contains("expected array"),
        "Error should mention expected format: {}",
        err
    );
}

/// Test that get_solver_public_key handles 32-byte Ed25519 public key
/// What is tested: Real-world Ed25519 public key format (32 bytes)
/// Why: Ed25519 public keys are exactly 32 bytes
#[tokio::test]
async fn test_get_solver_public_key_ed25519_format() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;
    // 32-byte Ed25519 public key
    let public_key: Vec<u8> = (0..32).collect();

    let (_mock_server, client) = setup_mock_server_with_public_key(
        solver_registry_addr,
        solver_addr,
        Some(&public_key),
    )
    .await;

    let result = client
        .get_solver_public_key(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let pk = result.unwrap();
    assert_eq!(pk, Some(public_key), "Should return 32-byte public key");
    assert_eq!(pk.unwrap().len(), 32, "Public key should be 32 bytes");
}

/// Test that get_solver_public_key errors on empty array response
/// What is tested: Empty array response results in error
/// Why: Aptos should return at least one element for a view function return value
#[tokio::test]
async fn test_get_solver_public_key_errors_on_empty_array() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;

    let mock_server = MockServer::start().await;
    let view_response = json!([]);

    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .respond_with(ResponseTemplate::new(200).set_body_json(view_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_public_key(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_err(), "Should error on empty array");
    let err = result.unwrap_err();
    assert!(
        err.to_string().contains("Empty response array"),
        "Error should mention empty array: {}",
        err
    );
}

/// Test that get_solver_public_key errors on non-string element
/// What is tested: Non-string element in array results in error
/// Why: Aptos returns hex string, not raw numbers
#[tokio::test]
async fn test_get_solver_public_key_errors_on_non_string_element() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;

    let mock_server = MockServer::start().await;
    // Return number instead of hex string
    let view_response = json!([12345]); // Invalid: number instead of hex string

    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .respond_with(ResponseTemplate::new(200).set_body_json(view_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_public_key(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_err(), "Should error on non-string element");
    let err = result.unwrap_err();
    assert!(
        err.to_string().contains("expected hex string"),
        "Error should mention expected hex string: {}",
        err
    );
}

/// Test that get_solver_public_key errors on invalid hex string
/// What is tested: Invalid hex characters result in error
/// Why: Hex decode should fail on invalid characters
#[tokio::test]
async fn test_get_solver_public_key_errors_on_invalid_hex() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;

    let mock_server = MockServer::start().await;
    // Return invalid hex string (contains 'Z' which is not hex)
    let view_response = json!(["0xZZZZinvalidhex"]);

    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .respond_with(ResponseTemplate::new(200).set_body_json(view_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_public_key(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_err(), "Should error on invalid hex");
    let err = result.unwrap_err();
    assert!(
        err.to_string().contains("Failed to decode hex"),
        "Error should mention hex decode failure: {}",
        err
    );
}

/// Test that get_solver_public_key errors on HTTP error
/// What is tested: HTTP error from view function results in error
/// Why: Network/server errors should be surfaced, not silently ignored
#[tokio::test]
async fn test_get_solver_public_key_errors_on_http_error() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;

    let mock_server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .respond_with(ResponseTemplate::new(500).set_body_string("Internal Server Error"))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_public_key(solver_addr, solver_registry_addr)
        .await;

    assert!(result.is_err(), "Should error on HTTP error");
    let err = result.unwrap_err();
    assert!(
        err.to_string().contains("Failed to query solver public key"),
        "Error should mention query failure: {}",
        err
    );
}

/// Test that get_solver_public_key rejects addresses without 0x prefix
/// What is tested: Address validation rejects malformed addresses
/// Why: Addresses must have 0x prefix - missing prefix indicates a bug in calling code
#[tokio::test]
async fn test_get_solver_public_key_rejects_address_without_prefix() {
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;
    // Address WITHOUT 0x prefix - this should be rejected
    let solver_addr_no_prefix = &DUMMY_SOLVER_ADDR_MVM_HUB[2..]; // Remove 0x prefix

    let mock_server = MockServer::start().await;
    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_public_key(solver_addr_no_prefix, solver_registry_addr)
        .await;

    assert!(result.is_err(), "Should reject address without 0x prefix");
    let err = result.unwrap_err();
    assert!(
        err.to_string().contains("must start with 0x prefix"),
        "Error should mention missing 0x prefix: {}",
        err
    );
}
