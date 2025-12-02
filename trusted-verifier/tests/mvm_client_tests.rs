//! Unit tests for MVM client functions
//!
//! These tests verify that MVM client functions work correctly,
//! including resource queries and registry lookups.

use serde_json::json;
use trusted_verifier::mvm_client::MvmClient;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

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
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

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
    let connected_chain_mvm_address =
        "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";

    let (_mock_server, client) = setup_mock_server_with_registry(
        registry_address,
        solver_address,
        Some(connected_chain_mvm_address),
    )
    .await;

    let result = client
        .get_solver_connected_chain_mvm_address(solver_address, registry_address)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address,
        Some(connected_chain_mvm_address.to_string()),
        "Should return the connected chain MVM address"
    );
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
    )
    .await;

    let result = client
        .get_solver_connected_chain_mvm_address(solver_address, registry_address)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address, None,
        "Should return None when no connected chain MVM address is set"
    );
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
    )
    .await;

    let result = client
        .get_solver_connected_chain_mvm_address(
            unregistered_solver, // Query for unregistered solver
            registry_address,
        )
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address, None,
        "Should return None when solver is not registered"
    );
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
        .respond_with(ResponseTemplate::new(200).set_body_json(json!([]))) // Empty resources
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_connected_chain_mvm_address(solver_address, registry_address)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address, None,
        "Should return None when registry resource is not found"
    );
}

/// Test that get_solver_connected_chain_mvm_address handles address normalization (with/without 0x prefix)
/// Why: Verify that address matching works regardless of 0x prefix
#[tokio::test]
async fn test_get_solver_connected_chain_mvm_address_address_normalization() {
    let registry_address = "0x1";
    let solver_address_with_prefix =
        "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let solver_address_without_prefix =
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let connected_chain_mvm_address =
        "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";

    let (_mock_server, client) = setup_mock_server_with_registry(
        registry_address,
        solver_address_with_prefix, // Registry has address with 0x prefix
        Some(connected_chain_mvm_address),
    )
    .await;

    // Query with address without 0x prefix
    let result = client
        .get_solver_connected_chain_mvm_address(solver_address_without_prefix, registry_address)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address,
        Some(connected_chain_mvm_address.to_string()),
        "Should return the connected chain MVM address regardless of 0x prefix"
    );
}

/// Create a mock SolverRegistry resource response with EVM address in hex string format
/// This tests the case where Aptos serializes Option<vector<u8>> as {"vec": ["0xhexstring"]}
/// instead of {"vec": [[bytes_array]]}
fn create_solver_registry_resource_with_evm_address_hex_string(
    registry_address: &str,
    solver_address: &str,
    evm_address: Option<&str>,
) -> serde_json::Value {
    let solver_entry = if let Some(evm_addr) = evm_address {
        // SolverInfo with connected_chain_evm_address set as hex string (Aptos serialization format)
        json!({
            "key": solver_address,
            "value": {
                "public_key": [1, 2, 3, 4], // Dummy public key bytes
                "connected_chain_evm_address": {"vec": [evm_addr]}, // Some(vector<u8>) as hex string
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

/// Create a mock SolverRegistry resource response with EVM address in array format
/// This tests the case where Aptos serializes Option<vector<u8>> as {"vec": [[bytes_array]]}
fn create_solver_registry_resource_with_evm_address_array(
    registry_address: &str,
    solver_address: &str,
    evm_address: Option<&str>,
) -> serde_json::Value {
    let solver_entry = if let Some(evm_addr) = evm_address {
        // Convert hex string (with or without 0x) to vector<u8> as array
        let addr_clean = evm_addr.strip_prefix("0x").unwrap_or(evm_addr);
        let bytes: Vec<u64> = (0..addr_clean.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&addr_clean[i..i + 2], 16).unwrap() as u64)
            .collect();

        // SolverInfo with connected_chain_evm_address set as byte array
        json!({
            "key": solver_address,
            "value": {
                "public_key": [1, 2, 3, 4], // Dummy public key bytes
                "connected_chain_evm_address": {"vec": [bytes]}, // Some(vector<u8>) as array
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

/// Test that get_solver_evm_address handles array format from Aptos
/// Why: Aptos can serialize Option<vector<u8>> as {"vec": [[bytes_array]]}
/// This test verifies we correctly parse the array format
#[tokio::test]
async fn test_get_solver_evm_address_array_format() {
    let mock_server = MockServer::start().await;
    let registry_address = "0x1";
    let solver_address = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    let evm_address = "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc";

    let resources_response = create_solver_registry_resource_with_evm_address_array(
        registry_address,
        solver_address,
        Some(evm_address),
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", registry_address)))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_evm_address(solver_address, registry_address)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address,
        Some(evm_address.to_string()),
        "Should return the EVM address when serialized as array format"
    );
}

/// Test that get_solver_evm_address handles hex string format from Aptos
/// Why: Aptos can serialize Option<vector<u8>> as {"vec": ["0xhexstring"]} instead of {"vec": [[bytes]]}
/// This test verifies we correctly parse the hex string format (the format that caused EVM outflow validation failures)
#[tokio::test]
async fn test_get_solver_evm_address_hex_string_format() {
    let mock_server = MockServer::start().await;
    let registry_address = "0x1";
    let solver_address = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    let evm_address = "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc";

    let resources_response = create_solver_registry_resource_with_evm_address_hex_string(
        registry_address,
        solver_address,
        Some(evm_address),
    );

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", registry_address)))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_evm_address(solver_address, registry_address)
        .await;

    assert!(result.is_ok(), "Query should succeed");
    let address = result.unwrap();
    assert_eq!(
        address,
        Some(evm_address.to_string()),
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
    registry_address_in_type: &str,
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
        "type": format!("{}::solver_registry::SolverRegistry", registry_address_in_type),
        "data": {
            "solvers": {
                "data": [solver_entry]
            }
        }
    }])
}

/// Test that get_solver_connected_chain_mvm_address handles leading zero mismatch
/// Why: Move strips leading zeros from addresses in type names (e.g., 0x0a4c... becomes 0xa4c...)
///      but the registry address passed to the function may have leading zeros.
#[tokio::test]
async fn test_get_solver_mvm_address_leading_zero_mismatch() {
    let mock_server = MockServer::start().await;

    // Registry address with leading zero after 0x prefix
    let registry_address_full = "0x0a4c86da5e0c1ce855d13c1e21025f40fa121e6b4ba8fc09c992f28fb06dc89e";
    // Same address but Move strips the leading zero in type names
    let registry_address_stripped = "0xa4c86da5e0c1ce855d13c1e21025f40fa121e6b4ba8fc09c992f28fb06dc89e";
    let solver_address = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let connected_chain_mvm_address =
        "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";

    // Mock response has the type with stripped leading zero (like Move does)
    let resources_response = create_solver_registry_resource_with_stripped_zeros(
        registry_address_stripped,
        solver_address,
        Some(connected_chain_mvm_address),
    );

    // But the API endpoint uses the full address
    Mock::given(method("GET"))
        .and(path(format!(
            "/v1/accounts/{}/resources",
            registry_address_full
        )))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    // Query with the full address (with leading zero)
    let result = client
        .get_solver_connected_chain_mvm_address(solver_address, registry_address_full)
        .await;

    assert!(
        result.is_ok(),
        "Query should succeed despite leading zero mismatch"
    );
    let address = result.unwrap();
    assert_eq!(
        address,
        Some(connected_chain_mvm_address.to_string()),
        "Should find the SolverRegistry despite leading zero being stripped in type name"
    );
}

/// Test that get_solver_evm_address handles leading zero mismatch
/// Why: Same as above, but for EVM address lookup
#[tokio::test]
async fn test_get_solver_evm_address_leading_zero_mismatch() {
    let mock_server = MockServer::start().await;

    // Registry address with leading zero
    let registry_address_full = "0x0a4c86da5e0c1ce855d13c1e21025f40fa121e6b4ba8fc09c992f28fb06dc89e";
    // Move strips the leading zero in type names
    let registry_address_stripped = "0xa4c86da5e0c1ce855d13c1e21025f40fa121e6b4ba8fc09c992f28fb06dc89e";
    let solver_address = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let evm_address = "0x1234567890123456789012345678901234567890";

    // Create mock response with stripped leading zero in type name
    let solver_entry = json!({
        "key": solver_address,
        "value": {
            "public_key": [1, 2, 3, 4],
            "connected_chain_evm_address": {"vec": [evm_address]},
            "connected_chain_mvm_address": {"vec": []},
            "registered_at": 1234567890
        }
    });

    let resources_response = json!([{
        "type": format!("{}::solver_registry::SolverRegistry", registry_address_stripped),
        "data": {
            "solvers": {
                "data": [solver_entry]
            }
        }
    }]);

    Mock::given(method("GET"))
        .and(path(format!(
            "/v1/accounts/{}/resources",
            registry_address_full
        )))
        .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    // Query with the full address (with leading zero)
    let result = client
        .get_solver_evm_address(solver_address, registry_address_full)
        .await;

    assert!(
        result.is_ok(),
        "Query should succeed despite leading zero mismatch"
    );
    let address = result.unwrap();
    assert_eq!(
        address,
        Some(evm_address.to_string()),
        "Should find the SolverRegistry despite leading zero being stripped in type name"
    );
}

// ============================================================================
// GET_SOLVER_PUBLIC_KEY TESTS
// ============================================================================

/// Setup a mock server that responds to get_public_key view function calls
async fn setup_mock_server_with_public_key(
    _registry_address: &str,
    _solver_address: &str,
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
    let registry_address = "0x1";
    let solver_address = "0xabc";
    let public_key = vec![1u8, 2u8, 3u8, 4u8, 5u8]; // Test public key

    let (_mock_server, client) = setup_mock_server_with_public_key(
        registry_address,
        solver_address,
        Some(&public_key),
    )
    .await;

    let result = client
        .get_solver_public_key(solver_address, registry_address)
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
    let registry_address = "0x1";
    let solver_address = "0xabc";

    let (_mock_server, client) = setup_mock_server_with_public_key(
        registry_address,
        solver_address,
        None, // No public key = not registered
    )
    .await;

    let result = client
        .get_solver_public_key(solver_address, registry_address)
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
    let registry_address = "0x1";
    let solver_address = "0xabc";

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
        .get_solver_public_key(solver_address, registry_address)
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
    let registry_address = "0x1";
    let solver_address = "0xabc";

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
        .get_solver_public_key(solver_address, registry_address)
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
    let registry_address = "0x1";
    let solver_address = "0xabc";
    // 32-byte Ed25519 public key
    let public_key: Vec<u8> = (0..32).collect();

    let (_mock_server, client) = setup_mock_server_with_public_key(
        registry_address,
        solver_address,
        Some(&public_key),
    )
    .await;

    let result = client
        .get_solver_public_key(solver_address, registry_address)
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
    let registry_address = "0x1";
    let solver_address = "0xabc";

    let mock_server = MockServer::start().await;
    let view_response = json!([]);

    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .respond_with(ResponseTemplate::new(200).set_body_json(view_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_public_key(solver_address, registry_address)
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
    let registry_address = "0x1";
    let solver_address = "0xabc";

    let mock_server = MockServer::start().await;
    // Return number instead of hex string
    let view_response = json!([12345]);

    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .respond_with(ResponseTemplate::new(200).set_body_json(view_response))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_public_key(solver_address, registry_address)
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
    let registry_address = "0x1";
    let solver_address = "0xabc";

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
        .get_solver_public_key(solver_address, registry_address)
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
    let registry_address = "0x1";
    let solver_address = "0xabc";

    let mock_server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .respond_with(ResponseTemplate::new(500).set_body_string("Internal Server Error"))
        .mount(&mock_server)
        .await;

    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_public_key(solver_address, registry_address)
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
    let registry_address = "0x1";
    // Address WITHOUT 0x prefix - this should be rejected
    let solver_address_no_prefix = "781a856e472a8cbc280cc979a6e3225355369dcea2980f7a4f00a1c4d09606f7";

    let mock_server = MockServer::start().await;
    let client = MvmClient::new(&mock_server.uri()).expect("Failed to create MvmClient");

    let result = client
        .get_solver_public_key(solver_address_no_prefix, registry_address)
        .await;

    assert!(result.is_err(), "Should reject address without 0x prefix");
    let err = result.unwrap_err();
    assert!(
        err.to_string().contains("must start with 0x prefix"),
        "Error should mention missing 0x prefix: {}",
        err
    );
}
