//! Unit tests for Aptos transaction extraction and validation logic
//!
//! These tests verify that transaction parameters can be correctly extracted
//! from Aptos transactions for outflow fulfillment validation.

use trusted_verifier::validator::{extract_aptos_fulfillment_params, validate_outflow_fulfillment, FulfillmentTransactionParams};
use trusted_verifier::validator::CrossChainValidator;
use trusted_verifier::aptos_client::AptosTransaction;
use trusted_verifier::monitor::RequestIntentEvent;
#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::{build_test_config, create_base_request_intent, create_base_fulfillment_transaction_params, create_base_aptos_transaction};

// ============================================================================
// APTOS TRANSACTION EXTRACTION TESTS
// ============================================================================

/// Test that extract_aptos_fulfillment_params successfully extracts parameters from valid Aptos transaction
/// 
/// What is tested: Extracting intent_id, recipient, amount, solver, and token_metadata from a valid
/// Aptos transaction that calls utils::transfer_with_intent_id().
/// 
/// Why: Verify that the extraction function correctly parses Aptos transaction payloads
/// to extract all required parameters for validation.
#[test]
fn test_extract_aptos_fulfillment_params_success() {
    let tx = AptosTransaction {
        payload: Some(serde_json::json!({
            "function": "0x123::utils::transfer_with_intent_id",
            "arguments": [
                "0x742d35cc6634c0532925a3b844bc9e7595f0beb",
                "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
                "0x17d7840",
                "0x1111111111111111111111111111111111111111111111111111111111111111"
            ]
        })),
        ..create_base_aptos_transaction()
    };

    let result = extract_aptos_fulfillment_params(&tx);

    assert!(result.is_ok(), "Extraction should succeed for valid transaction");
    let params = result.unwrap();
    assert_eq!(params.recipient, "0x742d35cc6634c0532925a3b844bc9e7595f0beb");
    assert_eq!(params.amount, 25000000u64); // 0x17d7840 in decimal
    assert_eq!(params.intent_id, "0x1111111111111111111111111111111111111111111111111111111111111111");
    assert_eq!(params.solver, "0xsolver123456789012345678901234567890123456789012345678901234567890");
    assert_eq!(params.token_metadata, "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef");
}

/// Test that extract_aptos_fulfillment_params fails when transaction is not a transfer_with_intent_id call
/// 
/// What is tested: Attempting to extract parameters from an Aptos transaction that doesn't call
/// utils::transfer_with_intent_id() should fail with an appropriate error.
/// 
/// Why: Verify that the extraction function correctly identifies and rejects transactions
/// that are not the expected fulfillment transaction type.
#[test]
fn test_extract_aptos_fulfillment_params_wrong_function() {
    let tx = AptosTransaction {
        payload: Some(serde_json::json!({
            "function": "0x123::utils::transfer",
            "arguments": ["0xrecipient", "0xmetadata", "0x100"]
        })),
        ..create_base_aptos_transaction()
    };

    let result = extract_aptos_fulfillment_params(&tx);

    assert!(result.is_err(), "Extraction should fail for wrong function");
    let error_msg = result.unwrap_err().to_string();
    assert!(error_msg.contains("transfer_with_intent_id") ||
            error_msg.contains("not a transfer_with_intent_id"));
}

/// Test that extract_aptos_fulfillment_params fails when transaction payload is missing
/// 
/// What is tested: Attempting to extract parameters from an Aptos transaction without a payload
/// should fail with an appropriate error.
/// 
/// Why: Verify that the extraction function handles missing payload gracefully.
#[test]
fn test_extract_aptos_fulfillment_params_missing_payload() {
    let tx = AptosTransaction {
        payload: None,
        ..create_base_aptos_transaction()
    };

    let result = extract_aptos_fulfillment_params(&tx);

    assert!(result.is_err(), "Extraction should fail when payload is missing");
    assert!(result.unwrap_err().to_string().contains("payload"));
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
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    let request_intent = RequestIntentEvent {
        desired_amount: 25000000,
        requester_address_connected_chain: Some("0x742d35cc6634c0532925a3b844bc9e7595f0beb".to_string()),
        reserved_solver: Some("0xsolver123456789012345678901234567890123456789012345678901234567890".to_string()),
        ..create_base_request_intent()
    };
    
    let tx_params = FulfillmentTransactionParams {
        recipient: "0x742d35cc6634c0532925a3b844bc9e7595f0beb".to_string(),
        amount: 25000000,
        solver: "0xsolver123456789012345678901234567890123456789012345678901234567890".to_string(),
        ..create_base_fulfillment_transaction_params()
    };
    
    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, true);
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(validation_result.valid, "Validation should pass when all parameters match");
}

/// Test that validate_outflow_fulfillment fails when transaction was not successful
/// 
/// What is tested: Validating an outflow fulfillment transaction where the transaction failed
/// should result in validation failure.
/// 
/// Why: Verify that only successful transactions can fulfill intents.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_unsuccessful_tx() {
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    let request_intent = create_base_request_intent();
    let tx_params = FulfillmentTransactionParams {
        intent_id: request_intent.intent_id.clone(),
        amount: request_intent.desired_amount,
        ..create_base_fulfillment_transaction_params()
    };
    
    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, false);
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(!validation_result.valid, "Validation should fail when transaction was not successful");
    assert!(validation_result.message.contains("not successful") ||
            validation_result.message.contains("successful"));
}

/// Test that validate_outflow_fulfillment fails when intent_id doesn't match
/// 
/// What is tested: Validating an outflow fulfillment transaction where the transaction's intent_id
/// doesn't match the request intent's intent_id should result in validation failure.
/// 
/// Why: Verify that transactions can only fulfill the specific intent they reference.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_intent_id_mismatch() {
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    let request_intent = create_base_request_intent();
    let tx_params = FulfillmentTransactionParams {
        intent_id: "0xwrong_intent_id".to_string(), // Different intent_id
        amount: request_intent.desired_amount,
        ..create_base_fulfillment_transaction_params()
    };
    
    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, true);
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(!validation_result.valid, "Validation should fail when intent_id doesn't match");
    assert!(validation_result.message.contains("intent_id") || validation_result.message.contains("match"));
}

/// Test that validate_outflow_fulfillment fails when recipient doesn't match requester_address_connected_chain
/// 
/// What is tested: Validating an outflow fulfillment transaction where the transaction's recipient
/// doesn't match the request intent's requester_address_connected_chain should result in validation failure.
/// 
/// Why: Verify that tokens are sent to the correct recipient address on the connected chain.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_recipient_mismatch() {
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    let request_intent = RequestIntentEvent {
        requester_address_connected_chain: Some("0xcorrect_recipient".to_string()),
        ..create_base_request_intent()
    };
    
    let tx_params = FulfillmentTransactionParams {
        recipient: "0xwrong_recipient".to_string(), // Different recipient
        amount: request_intent.desired_amount,
        ..create_base_fulfillment_transaction_params()
    };
    
    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, true);
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(!validation_result.valid, "Validation should fail when recipient doesn't match");
    assert!(validation_result.message.contains("recipient") || validation_result.message.contains("requester"));
}

/// Test that validate_outflow_fulfillment fails when amount doesn't match desired_amount
/// 
/// What is tested: Validating an outflow fulfillment transaction where the transaction's amount
/// doesn't match the request intent's desired_amount should result in validation failure.
/// 
/// Why: Verify that the correct amount of tokens is transferred.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_amount_mismatch() {
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    let request_intent = RequestIntentEvent {
        desired_amount: 1000,
        requester_address_connected_chain: Some("0xrecipient".to_string()), // Required for outflow validation
        ..create_base_request_intent()
    };
    
    let tx_params = FulfillmentTransactionParams {
        amount: 500, // Different amount
        ..create_base_fulfillment_transaction_params()
    };
    
    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, true);
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(!validation_result.valid, "Validation should fail when amount doesn't match");
    assert!(validation_result.message.contains("amount") || 
            validation_result.message.contains("Amount") ||
            validation_result.message.contains("Transaction amount") ||
            validation_result.message.contains("does not match") ||
            validation_result.message.contains("desired amount"));
}

/// Test that validate_outflow_fulfillment fails when solver doesn't match reserved solver
/// 
/// What is tested: Validating an outflow fulfillment transaction where the transaction's solver
/// doesn't match the request intent's reserved solver should result in validation failure.
/// 
/// Why: Verify that only the authorized solver can fulfill the intent.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_solver_mismatch() {
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    let request_intent = RequestIntentEvent {
        reserved_solver: Some("0xauthorized_solver".to_string()),
        requester_address_connected_chain: Some("0xrecipient".to_string()), // Required for outflow validation
        ..create_base_request_intent()
    };
    
    let tx_params = FulfillmentTransactionParams {
        amount: request_intent.desired_amount,
        solver: "0xunauthorized_solver".to_string(), // Different solver
        ..create_base_fulfillment_transaction_params()
    };
    
    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, true);
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(!validation_result.valid, "Validation should fail when solver doesn't match");
    assert!(validation_result.message.contains("solver") || 
            validation_result.message.contains("Solver") ||
            validation_result.message.contains("Transaction solver") ||
            validation_result.message.contains("does not match") ||
            validation_result.message.contains("reserved solver"));
}

