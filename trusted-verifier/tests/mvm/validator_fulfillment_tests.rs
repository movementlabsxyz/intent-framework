//! Unit tests for Move VM transaction extraction and validation logic
//!
//! These tests verify that transaction parameters can be correctly extracted
//! from Move VM transactions for outflow fulfillment validation.

use serde_json::json;
use trusted_verifier::monitor::RequestIntentEvent;
use trusted_verifier::mvm_client::MvmTransaction;
use trusted_verifier::validator::CrossChainValidator;
use trusted_verifier::validator::{
    extract_mvm_fulfillment_params, validate_outflow_fulfillment, FulfillmentTransactionParams,
};
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};
#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::{
    build_test_config_with_mvm, create_base_fulfillment_transaction_params_mvm,
    create_base_mvm_transaction, create_base_request_intent_mvm,
};

// ============================================================================
// MOVE VM TRANSACTION EXTRACTION TESTS
// ============================================================================

/// Test that extract_mvm_fulfillment_params successfully extracts parameters from valid Move VM transaction
///
/// What is tested: Extracting intent_id, recipient, amount, solver, and token_metadata from a valid
/// Move VM transaction that calls utils::transfer_with_intent_id().
///
/// Why: Verify that the extraction function correctly parses Move VM transaction payloads
/// to extract all required parameters for validation.
#[test]
fn test_extract_mvm_fulfillment_params_success() {
    let tx = MvmTransaction {
        payload: Some(serde_json::json!({
            "function": "0x123::utils::transfer_with_intent_id",
            "arguments": [
                "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                "0x17d7840",
                "0x1111111111111111111111111111111111111111111111111111111111111111"
            ]
        })),
        ..create_base_mvm_transaction()
    };

    let result = extract_mvm_fulfillment_params(&tx);

    assert!(
        result.is_ok(),
        "Extraction should succeed for valid transaction"
    );
    let params = result.unwrap();
    assert_eq!(
        params.recipient,
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    );
    assert_eq!(params.amount, 25000000); // 0x17d7840 in decimal
    assert_eq!(
        params.intent_id,
        "0x1111111111111111111111111111111111111111111111111111111111111111"
    );
    assert_eq!(
        params.solver,
        "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    );
    assert_eq!(
        params.token_metadata,
        "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    );
}

/// Test that extract_mvm_fulfillment_params handles amount as JSON number
///
/// What is tested: Extracting amount when Aptos serializes it as a JSON number (when passed as decimal to aptos CLI).
///
/// Why: Aptos CLI accepts decimal format (u64:100000000) but serializes it as a JSON number in the transaction payload.
#[test]
fn test_extract_mvm_fulfillment_params_amount_as_number() {
    let tx = MvmTransaction {
        payload: Some(serde_json::json!({
            "function": "0x123::utils::transfer_with_intent_id",
            "arguments": [
                "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                100000000u64, // Amount as JSON number (when passed as u64:100000000 to aptos CLI)
                "0x1111111111111111111111111111111111111111111111111111111111111111"
            ]
        })),
        ..create_base_mvm_transaction()
    };

    let result = extract_mvm_fulfillment_params(&tx);

    assert!(
        result.is_ok(),
        "Extraction should succeed when amount is a JSON number"
    );
    let params = result.unwrap();
    assert_eq!(params.amount, 100000000);
}

/// Test that extract_mvm_fulfillment_params handles amount as decimal string
///
/// What is tested: Extracting amount when Aptos serializes it as a decimal string (without 0x prefix).
///
/// Why: Aptos may serialize u64 values as decimal strings "100000000" instead of hex strings or JSON numbers.
#[test]
fn test_extract_mvm_fulfillment_params_amount_as_decimal_string() {
    let tx = MvmTransaction {
        payload: Some(serde_json::json!({
            "function": "0x123::utils::transfer_with_intent_id",
            "arguments": [
                "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                "100000000", // Amount as decimal string (without 0x prefix)
                "0x1111111111111111111111111111111111111111111111111111111111111111"
            ]
        })),
        ..create_base_mvm_transaction()
    };

    let result = extract_mvm_fulfillment_params(&tx);

    assert!(
        result.is_ok(),
        "Extraction should succeed when amount is a decimal string"
    );
    let params = result.unwrap();
    assert_eq!(params.amount, 100000000);
}

/// Test that extract_mvm_fulfillment_params fails when transaction is not a transfer_with_intent_id call
///
/// What is tested: Attempting to extract parameters from a Move VM transaction that doesn't call
/// utils::transfer_with_intent_id() should fail with an appropriate error.
///
/// Why: Verify that the extraction function correctly identifies and rejects transactions
/// that are not the expected fulfillment transaction type.
#[test]
fn test_extract_mvm_fulfillment_params_wrong_function() {
    let tx = MvmTransaction {
        payload: Some(serde_json::json!({
            "function": "0x123::utils::transfer",
            "arguments": ["0xrecipient", "0xmetadata", "0x100"]
        })),
        ..create_base_mvm_transaction()
    };

    let result = extract_mvm_fulfillment_params(&tx);

    assert!(result.is_err(), "Extraction should fail for wrong function");
    let error_msg = result.unwrap_err().to_string();
    assert!(
        error_msg.contains("transfer_with_intent_id")
            || error_msg.contains("not a transfer_with_intent_id")
    );
}

/// Test that extract_mvm_fulfillment_params fails when transaction payload is missing
///
/// What is tested: Attempting to extract parameters from a Move VM transaction without a payload
/// should fail with an appropriate error.
///
/// Why: Verify that the extraction function handles missing payload gracefully.
#[test]
fn test_extract_mvm_fulfillment_params_missing_payload() {
    let tx = MvmTransaction {
        payload: None,
        ..create_base_mvm_transaction()
    };

    let result = extract_mvm_fulfillment_params(&tx);

    assert!(
        result.is_err(),
        "Extraction should fail when payload is missing"
    );
    assert!(result.unwrap_err().to_string().contains("payload"));
}

/// Test that extract_mvm_fulfillment_params normalizes addresses with missing leading zeros
///
/// What is tested: Extracting parameters from a Move VM transaction where addresses
/// are missing leading zeros (e.g., 62 hex chars instead of 64) should be normalized
/// to 64 hex characters with leading zeros.
///
/// Why: Move VM addresses can be serialized without leading zeros, but validation
/// requires exactly 64 hex characters. This test ensures addresses are properly normalized.
#[test]
fn test_extract_mvm_fulfillment_params_address_normalization() {
    // Address without leading zeros: eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee (62 chars)
    // Should be normalized to: 00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee (64 chars)
    let recipient_short = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";

    let tx = MvmTransaction {
        payload: Some(serde_json::json!({
            "function": "0x123::utils::transfer_with_intent_id",
            "arguments": [
                recipient_short,
                "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                "100000000",
                "0x1111111111111111111111111111111111111111111111111111111111111111"
            ]
        })),
        sender: Some(
            "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(),
        ),
        ..create_base_mvm_transaction()
    };

    let result = extract_mvm_fulfillment_params(&tx);

    assert!(
        result.is_ok(),
        "Extraction should succeed and normalize addresses"
    );
    let params = result.unwrap();

    // Recipient should be normalized to 64 hex chars with leading zeros
    assert_eq!(
        params.recipient, "0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        "Recipient address should be padded to 64 hex characters"
    );

    // Intent ID is already 64 hex chars, so should remain unchanged
    assert_eq!(
        params.intent_id, "0x1111111111111111111111111111111111111111111111111111111111111111",
        "Intent ID should remain 64 hex characters (already correct length)"
    );
    assert_eq!(
        params.intent_id.len(),
        66, // 0x + 64 hex chars
        "Intent ID should be 66 characters (0x + 64 hex)"
    );

    // Solver should also be normalized (already 64 chars in test, but should still work)
    assert_eq!(
        params.solver.len(),
        66, // 0x + 64 hex chars
        "Solver address should be 66 characters (0x + 64 hex)"
    );
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Helper to create a mock SolverRegistry resource response with MVM address
fn create_solver_registry_resource_with_mvm_address(
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

// ============================================================================
// OUTFLOW FULFILLMENT VALIDATION TESTS
// ============================================================================

/// Test that validate_outflow_fulfillment succeeds when all parameters match
///
/// What is tested: Validating an outflow fulfillment transaction where transaction was successful,
/// intent_id matches, recipient matches requester_address_connected_chain, amount matches desired_amount,
/// and solver matches reserved solver.
///
/// Why: Verify that the validation function correctly validates all requirements for a successful
/// outflow fulfillment.
#[tokio::test]
async fn test_validate_outflow_fulfillment_success() {
    let solver_address = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let connected_chain_mvm_address =
        "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let registry_address = "0x1";

    let (_mock_server, validator) = setup_mock_server_with_registry(
        registry_address,
        solver_address,
        Some(connected_chain_mvm_address),
    )
    .await;

    let request_intent = RequestIntentEvent {
        desired_amount: 25000000, // For outflow request intents, validation uses desired_amount (amount desired on connected chain)
        reserved_solver: Some(solver_address.to_string()),
        ..create_base_request_intent_mvm()
    };

    let tx_params = FulfillmentTransactionParams {
        amount: 25000000,
        solver: connected_chain_mvm_address.to_string(),
        ..create_base_fulfillment_transaction_params_mvm()
    };

    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, true).await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        validation_result.valid,
        "Validation should pass when all parameters match and solver is registered"
    );
}

/// Test that validate_outflow_fulfillment fails when transaction was not successful
///
/// What is tested: Validating an outflow fulfillment transaction where the transaction failed
/// should result in validation failure.
///
/// Why: Verify that only successful transactions can fulfill intents.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_unsuccessful_tx() {
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let request_intent = create_base_request_intent_mvm();
    let tx_params = FulfillmentTransactionParams {
        intent_id: request_intent.intent_id.clone(),
        amount: request_intent.desired_amount,
        ..create_base_fulfillment_transaction_params_mvm()
    };

    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, false).await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        !validation_result.valid,
        "Validation should fail when transaction was not successful"
    );
    assert!(
        validation_result.message.contains("not successful")
            || validation_result.message.contains("successful")
    );
}

/// Test that validate_outflow_fulfillment fails when intent_id doesn't match
///
/// What is tested: Validating an outflow fulfillment transaction where the transaction's intent_id
/// doesn't match the request intent's intent_id should result in validation failure.
///
/// Why: Verify that transactions can only fulfill the specific intent they reference.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_intent_id_mismatch() {
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let request_intent = create_base_request_intent_mvm();
    let tx_params = FulfillmentTransactionParams {
        intent_id: "0xwrong_intent_id".to_string(), // Different intent_id
        amount: request_intent.desired_amount,
        ..create_base_fulfillment_transaction_params_mvm()
    };

    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, true).await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        !validation_result.valid,
        "Validation should fail when intent_id doesn't match"
    );
    assert!(
        validation_result.message.contains("intent_id")
            || validation_result.message.contains("match")
    );
}

/// Test that validate_outflow_fulfillment fails when recipient doesn't match requester_address_connected_chain
///
/// What is tested: Validating an outflow fulfillment transaction where the transaction's recipient
/// doesn't match the request intent's requester_address_connected_chain should result in validation failure.
///
/// Why: Verify that tokens are sent to the correct recipient address on the connected chain.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_recipient_mismatch() {
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let request_intent = create_base_request_intent_mvm();

    let tx_params = FulfillmentTransactionParams {
        recipient: "0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd".to_string(), // Different recipient (Move VM address format)
        amount: request_intent.desired_amount,
        ..create_base_fulfillment_transaction_params_mvm()
    };

    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, true).await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        !validation_result.valid,
        "Validation should fail when recipient doesn't match"
    );
    assert!(
        validation_result.message.contains("recipient")
            || validation_result.message.contains("requester")
    );
}

/// Test that validate_outflow_fulfillment fails when amount doesn't match desired_amount
///
/// What is tested: Validating an outflow fulfillment transaction where the transaction's amount
/// doesn't match the request intent's desired_amount should result in validation failure.
///
/// Why: Verify that the correct amount of tokens is transferred.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_amount_mismatch() {
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let request_intent = RequestIntentEvent {
        desired_amount: 1000,
        ..create_base_request_intent_mvm()
    };

    let tx_params = FulfillmentTransactionParams {
        amount: 500, // Different amount
        ..create_base_fulfillment_transaction_params_mvm()
    };

    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, true).await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        !validation_result.valid,
        "Validation should fail when amount doesn't match"
    );
    assert!(
        validation_result.message.contains("amount")
            || validation_result.message.contains("Amount")
            || validation_result.message.contains("Transaction amount")
            || validation_result.message.contains("does not match")
            || validation_result.message.contains("desired amount")
    );
}

/// Test that validate_outflow_fulfillment fails when reserved solver is not registered in hub registry
///
/// What is tested: Validating an outflow fulfillment transaction where the reserved solver
/// is not registered in the hub chain solver registry should result in validation failure.
///
/// Why: Verify that only registered solvers can fulfill intents.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_solver_not_registered() {
    let unregistered_solver = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let registry_address = "0x1";

    // Setup mock server with empty registry (solver not registered)
    let mock_server = MockServer::start().await;

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", registry_address)))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!([]))) // Empty resources
        .mount(&mock_server)
        .await;

    let mut config = build_test_config_with_mvm();
    config.hub_chain.rpc_url = mock_server.uri();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let request_intent = RequestIntentEvent {
        desired_amount: 1000, // Set desired_amount to avoid validation failure on amount check
        reserved_solver: Some(unregistered_solver.to_string()),
        ..create_base_request_intent_mvm()
    };

    let tx_params = FulfillmentTransactionParams {
        amount: request_intent.desired_amount,
        ..create_base_fulfillment_transaction_params_mvm()
    };

    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, true).await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    // The validation will fail because the reserved solver is not registered in the hub registry
    assert!(
        !validation_result.valid,
        "Validation should fail when reserved solver is not registered"
    );
    assert!(
        validation_result.message.contains("not registered")
            || validation_result.message.contains("registry")
            || validation_result.message.contains("solver")
            || validation_result.message.contains("Solver")
    );
}
