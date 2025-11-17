//! Unit tests for EVM transaction extraction and validation logic
//!
//! These tests verify that transaction parameters can be correctly extracted
//! from EVM transactions for outflow fulfillment validation.

use trusted_verifier::validator::{extract_evm_fulfillment_params, validate_outflow_fulfillment, FulfillmentTransactionParams};
use trusted_verifier::validator::CrossChainValidator;
use trusted_verifier::evm_client::EvmTransaction;
use trusted_verifier::monitor::RequestIntentEvent;
#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::{build_test_config, create_base_request_intent, create_base_fulfillment_transaction_params, create_base_evm_transaction};

// ============================================================================
// EVM TRANSACTION EXTRACTION TESTS
// ============================================================================

/// Test that extract_evm_fulfillment_params successfully extracts parameters from valid EVM transaction
/// 
/// What is tested: Extracting intent_id, recipient, amount, solver, and token_metadata from a valid
/// EVM transaction that calls ERC20 transfer() with intent_id appended in calldata.
/// 
/// Why: Verify that the extraction function correctly parses EVM transaction calldata
/// to extract all required parameters for validation.
#[test]
fn test_extract_evm_fulfillment_params_success() {
    // ERC20 transfer selector: 0xa9059cbb
    // Calldata: selector (4 bytes) + to (32 bytes) + amount (32 bytes) + intent_id (32 bytes)
    // to: 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa (padded to 32 bytes = 64 hex chars)
    // amount: 0x17d7840 = 25000000 (padded to 32 bytes = 64 hex chars)
    // intent_id: 0x1111111111111111111111111111111111111111111111111111111111111111 (64 hex chars)
    // Total: 8 (selector) + 64 (to) + 64 (amount) + 64 (intent_id) = 200 hex chars
    let calldata = "a9059cbb000000000000000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa00000000000000000000000000000000000000000000000000000000017d78401111111111111111111111111111111111111111111111111111111111111111";
    
    let tx = EvmTransaction {
        input: format!("0x{}", calldata),
        ..create_base_evm_transaction()
    };

    let result = extract_evm_fulfillment_params(&tx);

    assert!(result.is_ok(), "Extraction should succeed for valid transaction");
    let params = result.unwrap();
    // EVM addresses are 20 bytes, but stored as 32 bytes in calldata (padded with zeros at the start)
    // The extraction gets the full 32-byte value: 0x + 64 hex chars
    assert_eq!(params.recipient, "0x000000000000000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    assert_eq!(params.amount, 25000000u64); // 0x17d7840 in decimal
    assert_eq!(params.intent_id, "0x1111111111111111111111111111111111111111111111111111111111111111");
    assert_eq!(params.solver, "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    assert_eq!(params.token_metadata, "0xcccccccccccccccccccccccccccccccccccccccc");
    
    // Verify the transaction's `to` field is used for token_metadata
    assert_eq!(tx.to, Some("0xcccccccccccccccccccccccccccccccccccccccc".to_string()));
}

/// Test that extract_evm_fulfillment_params fails when transaction is not an ERC20 transfer call
/// 
/// What is tested: Attempting to extract parameters from an EVM transaction that doesn't call
/// ERC20 transfer() should fail with an appropriate error.
/// 
/// Why: Verify that the extraction function correctly identifies and rejects transactions
/// that are not ERC20 transfer calls.
#[test]
fn test_extract_evm_fulfillment_params_wrong_selector() {
    let tx = EvmTransaction {
        input: "0x12345678".to_string(), // Wrong selector
        ..create_base_evm_transaction()
    };

    let result = extract_evm_fulfillment_params(&tx);

    assert!(result.is_err(), "Extraction should fail for wrong selector");
    let error_msg = result.unwrap_err().to_string();
    assert!(error_msg.contains("ERC20 transfer") ||
            error_msg.contains("not an ERC20 transfer"));
}

/// Test that extract_evm_fulfillment_params fails when calldata is too short
/// 
/// What is tested: Attempting to extract parameters from an EVM transaction with insufficient
/// calldata length should fail with an appropriate error.
/// 
/// Why: Verify that the extraction function validates calldata length before parsing.
#[test]
fn test_extract_evm_fulfillment_params_insufficient_calldata() {
    let tx = EvmTransaction {
        input: "0xa9059cbb0000000000000000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(), // Too short - missing amount and intent_id
        ..create_base_evm_transaction()
    };

    let result = extract_evm_fulfillment_params(&tx);

    assert!(result.is_err(), "Extraction should fail when calldata is too short");
    let error_msg = result.unwrap_err().to_string();
    assert!(error_msg.contains("Insufficient") ||
            error_msg.contains("length"));
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
        requester_address_connected_chain: Some("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string()),
        ..create_base_request_intent()
    };
    
    let tx_params = FulfillmentTransactionParams {
        recipient: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        amount: 25000000,
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

