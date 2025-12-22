//! Unit tests for Move VM transaction extraction and validation logic
//!
//! These tests verify that transaction parameters can be correctly extracted
//! from Move VM transactions for outflow fulfillment validation.

use serde_json::json;
use trusted_verifier::monitor::IntentEvent;
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
    build_test_config_with_mvm, create_default_fulfillment_transaction_params_mvm,
    create_default_mvm_transaction, create_default_intent_mvm, setup_mock_server_with_registry_mvm,
    DUMMY_INTENT_ID, DUMMY_METADATA_ADDR_MVM, DUMMY_REQUESTER_ADDR_MVM_CON, DUMMY_SOLVER_ADDR_MVM_HUB, DUMMY_SOLVER_ADDR_MVM_CON,
    DUMMY_SOLVER_REGISTRY_ADDR,
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
                DUMMY_REQUESTER_ADDR_MVM_CON, // recipient
                DUMMY_METADATA_ADDR_MVM, // metadata object address
                "0x17d7840", // amount
                DUMMY_INTENT_ID // intent_id
            ]
        })),
        ..create_default_mvm_transaction()
    };

    let result = extract_mvm_fulfillment_params(&tx);

    assert!(
        result.is_ok(),
        "Extraction should succeed for valid transaction"
    );
    let params = result.unwrap();
    assert_eq!(
        params.recipient_addr,
        DUMMY_REQUESTER_ADDR_MVM_CON
    );
    assert_eq!(params.amount, 25000000); // 0x17d7840 in decimal
    assert_eq!(
        params.intent_id,
        DUMMY_INTENT_ID
    );
    assert_eq!(
        params.solver_addr,
        DUMMY_SOLVER_ADDR_MVM_CON
    );
    assert_eq!(
        params.token_metadata,
        DUMMY_METADATA_ADDR_MVM
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
                DUMMY_REQUESTER_ADDR_MVM_CON, // recipient
                DUMMY_METADATA_ADDR_MVM, // metadata object address
                100000000u64, // Amount as JSON number (when passed as u64:100000000 to aptos CLI)
                DUMMY_INTENT_ID // intent_id
            ]
        })),
        ..create_default_mvm_transaction()
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
                DUMMY_REQUESTER_ADDR_MVM_CON, // recipient
                DUMMY_METADATA_ADDR_MVM, // metadata object address
                "100000000", // Amount as decimal string (without 0x prefix)
                DUMMY_INTENT_ID // intent_id
            ]
        })),
        ..create_default_mvm_transaction()
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
        ..create_default_mvm_transaction()
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
        ..create_default_mvm_transaction()
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
    let recipient_short: &str = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";

    let tx = MvmTransaction {
        payload: Some(serde_json::json!({
            "function": "0x123::utils::transfer_with_intent_id",
            "arguments": [
                recipient_short,
                DUMMY_METADATA_ADDR_MVM, // metadata object address
                "100000000",
                DUMMY_INTENT_ID // intent_id
            ]
        })),
        sender: Some(
            DUMMY_SOLVER_ADDR_MVM_HUB.to_string(), // solver
        ),
        ..create_default_mvm_transaction()
    };

    let result = extract_mvm_fulfillment_params(&tx);

    assert!(
        result.is_ok(),
        "Extraction should succeed and normalize addresses"
    );
    let params = result.unwrap();

    // Recipient should be normalized to 64 hex chars with leading zeros
    assert_eq!(
        params.recipient_addr, "0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        "Recipient address should be padded to 64 hex characters"
    );

    // Intent ID is already 64 hex chars, so should remain unchanged
    assert_eq!(
        params.intent_id, DUMMY_INTENT_ID,
        "Intent ID should remain 64 hex characters (already correct length)"
    );
    assert_eq!(
        params.intent_id.len(),
        66, // 0x + 64 hex chars
        "Intent ID should be 66 characters (0x + 64 hex)"
    );

    // Solver should also be normalized (already 64 chars in test, but should still work)
    assert_eq!(
        params.solver_addr.len(),
        66, // 0x + 64 hex chars
        "Solver address should be 66 characters (0x + 64 hex)"
    );
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// ============================================================================
// OUTFLOW FULFILLMENT VALIDATION TESTS
// ============================================================================

/// Test that validate_outflow_fulfillment succeeds when all parameters match
///
/// What is tested: Validating an outflow fulfillment transaction where transaction was successful,
/// intent_id matches, recipient matches requester_addr_connected_chain, amount matches desired_amount,
/// and solver matches reserved solver.
///
/// Why: Verify that the validation function correctly validates all requirements for a successful
/// outflow fulfillment.
#[tokio::test]
async fn test_validate_outflow_fulfillment_success() {
    let solver_addr = DUMMY_SOLVER_ADDR_MVM_HUB;
    let solver_connected_chain_mvm_addr = DUMMY_SOLVER_ADDR_MVM_CON;
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;

    let (_mock_server, validator) = setup_mock_server_with_registry_mvm(
        solver_registry_addr,
        solver_addr,
        Some(solver_connected_chain_mvm_addr),
    )
    .await;

    let intent = IntentEvent {
        desired_amount: 25000000, // For outflow intents, validation uses desired_amount (amount desired on connected chain)
        reserved_solver_addr: Some(solver_addr.to_string()),
        ..create_default_intent_mvm()
    };

    let tx_params = FulfillmentTransactionParams {
        amount: 25000000,
        solver_addr: solver_connected_chain_mvm_addr.to_string(),
        ..create_default_fulfillment_transaction_params_mvm()
    };

    let result = validate_outflow_fulfillment(&validator, &intent, &tx_params, true).await;

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

    let intent = create_default_intent_mvm();
    let tx_params = FulfillmentTransactionParams {
        intent_id: intent.intent_id.clone(),
        amount: intent.desired_amount,
        ..create_default_fulfillment_transaction_params_mvm()
    };

    let result = validate_outflow_fulfillment(&validator, &intent, &tx_params, false).await;

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
/// doesn't match the intent's intent_id should result in validation failure.
///
/// Why: Verify that transactions can only fulfill the specific intent they reference.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_intent_id_mismatch() {
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let intent = create_default_intent_mvm();
    let tx_params = FulfillmentTransactionParams {
        intent_id: "0xwrong_intent_id".to_string(), // Different intent_id
        amount: intent.desired_amount,
        ..create_default_fulfillment_transaction_params_mvm()
    };

    let result = validate_outflow_fulfillment(&validator, &intent, &tx_params, true).await;

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

/// Test that validate_outflow_fulfillment fails when recipient doesn't match requester_addr_connected_chain
///
/// What is tested: Validating an outflow fulfillment transaction where the transaction's recipient
/// doesn't match the intent's requester_addr_connected_chain should result in validation failure.
///
/// Why: Verify that tokens are sent to the correct recipient address on the connected chain.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_recipient_mismatch() {
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let intent = create_default_intent_mvm();

    let tx_params = FulfillmentTransactionParams {
        recipient_addr: "0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd".to_string(), // Different recipient (Move VM address format)
        amount: intent.desired_amount,
        ..create_default_fulfillment_transaction_params_mvm()
    };

    let result = validate_outflow_fulfillment(&validator, &intent, &tx_params, true).await;

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
/// doesn't match the intent's desired_amount should result in validation failure.
///
/// Why: Verify that the correct amount of tokens is transferred.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_amount_mismatch() {
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let intent = IntentEvent {
        desired_amount: 1000,
        ..create_default_intent_mvm()
    };

    let tx_params = FulfillmentTransactionParams {
        amount: 500, // Different amount
        ..create_default_fulfillment_transaction_params_mvm()
    };

    let result = validate_outflow_fulfillment(&validator, &intent, &tx_params, true).await;

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
    let unregistered_solver = DUMMY_SOLVER_ADDR_MVM_HUB;
    let solver_registry_addr = DUMMY_SOLVER_REGISTRY_ADDR;

    // Setup mock server with empty registry (solver not registered)
    let mock_server = MockServer::start().await;

    Mock::given(method("GET"))
        .and(path(format!("/v1/accounts/{}/resources", solver_registry_addr)))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!([]))) // Empty resources
        .mount(&mock_server)
        .await;

    let mut config = build_test_config_with_mvm();
    config.hub_chain.rpc_url = mock_server.uri();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let intent = IntentEvent {
        desired_amount: 1000, // Set desired_amount to avoid validation failure on amount check
        reserved_solver_addr: Some(unregistered_solver.to_string()),
        ..create_default_intent_mvm()
    };

    let tx_params = FulfillmentTransactionParams {
        amount: intent.desired_amount,
        ..create_default_fulfillment_transaction_params_mvm()
    };

    let result = validate_outflow_fulfillment(&validator, &intent, &tx_params, true).await;

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
