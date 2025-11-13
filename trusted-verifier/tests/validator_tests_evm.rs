//! Unit tests for EVM solver registry validation
//!
//! These tests verify that EVM escrow solver validation works correctly,
//! including registry lookup, address matching, and error handling.

use trusted_verifier::validator::CrossChainValidator;
use trusted_verifier::monitor::RequestIntentEvent;
use trusted_verifier::config::Config;
use wiremock::{MockServer, Mock, ResponseTemplate};
use wiremock::matchers::{method, path, body_json};
use serde_json::json;
#[path = "mod.rs"]
mod test_helpers;
use test_helpers::{build_test_config, create_base_request_intent};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Build a test config with a mock server URL
fn build_test_config_with_mock_server(mock_server_url: &str) -> Config {
    let mut config = build_test_config();
    config.hub_chain.rpc_url = mock_server_url.to_string();
    config
}

/// Helper to create a mock response for get_solver_evm_address
/// Returns a vector of bytes representing the EVM address
fn create_evm_address_response(evm_address: Option<&str>) -> serde_json::Value {
    match evm_address {
        Some(addr) => {
            // Convert hex string (with or without 0x) to vector<u8>
            let addr_clean = addr.strip_prefix("0x").unwrap_or(addr);
            let bytes: Vec<u8> = (0..addr_clean.len())
                .step_by(2)
                .map(|i| u8::from_str_radix(&addr_clean[i..i+2], 16).unwrap())
                .collect();
            json!(bytes.iter().map(|b| *b as u64).collect::<Vec<u64>>())
        }
        None => json!([])
    }
}

/// Setup a mock server that responds to get_solver_evm_address calls
/// Returns the mock server and config
async fn setup_mock_server_with_evm_address_response(
    solver_address: &str,
    evm_address: Option<&str>,
) -> (MockServer, Config, CrossChainValidator) {
    let mock_server = MockServer::start().await;
    
    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .and(body_json(&json!({
            "function": "0x1::solver_registry::get_evm_address",
            "type_arguments": [],
            "arguments": [solver_address]
        })))
        .respond_with(ResponseTemplate::new(200)
            .set_body_json(create_evm_address_response(evm_address)))
        .mount(&mock_server)
        .await;
    
    let config = build_test_config_with_mock_server(&mock_server.uri());
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    (mock_server, config, validator)
}

/// Setup a mock server that returns an error response
async fn setup_mock_server_with_error(status_code: u16) -> (MockServer, Config, CrossChainValidator) {
    let mock_server = MockServer::start().await;
    
    Mock::given(method("POST"))
        .and(path("/v1/view"))
        .respond_with(ResponseTemplate::new(status_code))
        .mount(&mock_server)
        .await;
    
    let config = build_test_config_with_mock_server(&mock_server.uri());
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    (mock_server, config, validator)
}

/// Create a test request intent with the given solver
fn create_test_request_intent(solver: Option<String>) -> RequestIntentEvent {
    RequestIntentEvent {
        offered_metadata: "{}".to_string(),
        desired_metadata: "{}".to_string(),
        expiry_time: 1000000,
        reserved_solver: solver,
        connected_chain_id: Some(31337),
        ..create_base_request_intent()
    }
}

// ============================================================================
// TESTS
// ============================================================================

/// Test that validate_evm_escrow_solver succeeds when escrow reserved_solver matches registered EVM address
/// Why: Verify successful validation path when solver is registered and addresses match
#[tokio::test]
async fn test_successful_evm_solver_validation() {
    let _ = tracing_subscriber::fmt::try_init();
    
    let solver_address = "0xsolver_aptos";
    let registered_evm_address = "0x1234567890123456789012345678901234567890";
    let (_mock_server, config, validator) = setup_mock_server_with_evm_address_response(
        solver_address,
        Some(registered_evm_address),
    ).await;
    
    let request_intent = create_test_request_intent(Some(solver_address.to_string()));
    
    // Test with matching address
    let escrow_reserved_solver = registered_evm_address;
    let result = validator.validate_evm_escrow_solver(
        &request_intent,
        escrow_reserved_solver,
        &config.hub_chain.rpc_url,
        &config.hub_chain.intent_module_address,
    ).await;
    
    assert!(result.is_ok(), "Validation should succeed");
    let validation_result = result.unwrap();
    assert!(validation_result.valid, "Validation should be valid when addresses match");
    assert!(validation_result.message.contains("successful"), 
            "Message should indicate success");
}

/// Test that validate_evm_escrow_solver rejects when solver is not found in registry
/// Why: Verify error handling when solver is not registered
#[tokio::test]
async fn test_rejection_when_solver_not_registered() {
    let _ = tracing_subscriber::fmt::try_init();
    
    let solver_address = "0xunregistered_solver";
    let (_mock_server, config, validator) = setup_mock_server_with_evm_address_response(
        solver_address,
        None, // No EVM address (solver not registered)
    ).await;
    
    let request_intent = create_test_request_intent(Some(solver_address.to_string()));
    
    let escrow_reserved_solver = "0x1234567890123456789012345678901234567890";
    let result = validator.validate_evm_escrow_solver(
        &request_intent,
        escrow_reserved_solver,
        &config.hub_chain.rpc_url,
        &config.hub_chain.intent_module_address,
    ).await;
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(!validation_result.valid, "Validation should fail when solver is not registered");
    assert!(validation_result.message.contains("not registered") || 
            validation_result.message.contains("Solver"),
            "Error message should indicate solver not registered");
}

/// Test that validate_evm_escrow_solver rejects when registered EVM address doesn't match escrow reserved_solver
/// Why: Verify validation fails when addresses don't match
#[tokio::test]
async fn test_rejection_when_evm_addresses_dont_match() {
    let _ = tracing_subscriber::fmt::try_init();
    
    let solver_address = "0xsolver_aptos";
    let registered_evm_address = "0x1111111111111111111111111111111111111111";
    let (_mock_server, config, validator) = setup_mock_server_with_evm_address_response(
        solver_address,
        Some(registered_evm_address),
    ).await;
    
    let request_intent = create_test_request_intent(Some(solver_address.to_string()));
    
    // Escrow has a different address
    let escrow_reserved_solver = "0x2222222222222222222222222222222222222222";
    let result = validator.validate_evm_escrow_solver(
        &request_intent,
        escrow_reserved_solver,
        &config.hub_chain.rpc_url,
        &config.hub_chain.intent_module_address,
    ).await;
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(!validation_result.valid, "Validation should fail when addresses don't match");
    assert!(validation_result.message.contains("does not match") ||
            validation_result.message.contains("match"),
            "Error message should indicate address mismatch");
}

/// Test that EVM address comparison is case-insensitive and handles 0x prefix correctly
/// Why: Verify address normalization works correctly
#[tokio::test]
async fn test_evm_address_normalization() {
    let _ = tracing_subscriber::fmt::try_init();
    
    // Test cases: (escrow_address, registered_address, should_match)
    let test_cases = vec![
        ("0xABC123", "0xabc123", true),
        ("0xabc123", "0xABC123", true),
        ("ABC123", "0xabc123", true),  // Missing 0x prefix
        ("0xABC123", "abc123", true),  // Missing 0x prefix
        ("0xABC123", "0xDEF456", false), // Different addresses
    ];
    
    for (escrow_addr, registered_addr, should_match) in test_cases {
        let solver_address = "0xsolver_aptos";
        let (_mock_server, config, validator) = setup_mock_server_with_evm_address_response(
            solver_address,
            Some(registered_addr),
        ).await;
        
        let request_intent = create_test_request_intent(Some(solver_address.to_string()));
        
        let result = validator.validate_evm_escrow_solver(
            &request_intent,
            escrow_addr,
            &config.hub_chain.rpc_url,
            &config.hub_chain.intent_module_address,
        ).await;
        
        assert!(result.is_ok(), "Validation should complete");
        let validation_result = result.unwrap();
        assert_eq!(
            validation_result.valid, should_match,
            "Address normalization failed: escrow='{}', registered='{}', expected_match={}",
            escrow_addr, registered_addr, should_match
        );
    }
}

/// Test that validate_evm_escrow_solver handles network errors and timeouts gracefully
/// Why: Verify error handling for external service failures
#[tokio::test]
async fn test_error_handling_for_registry_query_failures() {
    let _ = tracing_subscriber::fmt::try_init();
    
    // Setup mock server that returns a 500 error (simulating network/server error)
    let (_mock_server, config, validator) = setup_mock_server_with_error(500).await;
    
    let request_intent = create_test_request_intent(Some("0xsolver_aptos".to_string()));
    
    let escrow_reserved_solver = "0x1234567890123456789012345678901234567890";
    let result = validator.validate_evm_escrow_solver(
        &request_intent,
        escrow_reserved_solver,
        &config.hub_chain.rpc_url,
        &config.hub_chain.intent_module_address,
    ).await;
    
    // When registry query fails, get_solver_evm_address returns Ok(None),
    // which is treated as "solver not registered" rather than a network error
    // This is the current behavior - errors are caught and treated as "not registered"
    assert!(result.is_ok(), "Validation should complete (errors are caught and treated as not registered)");
    let validation_result = result.unwrap();
    assert!(!validation_result.valid, "Validation should fail when registry query fails (treated as not registered)");
    assert!(validation_result.message.contains("not registered") ||
            validation_result.message.contains("Solver"),
            "Error message should indicate solver not registered (query failures are treated this way)");
}

