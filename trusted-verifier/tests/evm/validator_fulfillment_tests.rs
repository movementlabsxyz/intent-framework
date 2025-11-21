//! Unit tests for EVM transaction extraction and validation logic
//!
//! These tests verify that transaction parameters can be correctly extracted
//! from EVM transactions for outflow fulfillment validation.

use serde_json::json;
use trusted_verifier::evm_client::EvmTransaction;
use trusted_verifier::monitor::RequestIntentEvent;
use trusted_verifier::validator::CrossChainValidator;
use trusted_verifier::validator::{
    extract_evm_fulfillment_params, validate_outflow_fulfillment, FulfillmentTransactionParams,
};
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};
#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::{
    build_test_config_with_evm, create_base_evm_transaction,
    create_base_fulfillment_transaction_params_evm, create_base_request_intent_evm,
};

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

    assert!(
        result.is_ok(),
        "Extraction should succeed for valid transaction"
    );
    let params = result.unwrap();
    assert_eq!(
        params.recipient,
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    );
    assert_eq!(params.amount, 25000000); // 0x17d7840 in decimal
    assert_eq!(
        params.intent_id,
        "0x1111111111111111111111111111111111111111111111111111111111111111"
    );
    assert_eq!(params.solver, "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    assert_eq!(
        params.token_metadata,
        "0xcccccccccccccccccccccccccccccccccccccccc"
    );

    // Verify the transaction's `to` field is used for token_metadata
    assert_eq!(
        tx.to,
        Some("0xcccccccccccccccccccccccccccccccccccccccc".to_string())
    );
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
    assert!(error_msg.contains("ERC20 transfer") || error_msg.contains("not an ERC20 transfer"));
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
        input: "0xa9059cbb0000000000000000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            .to_string(), // Too short - missing amount and intent_id
        ..create_base_evm_transaction()
    };

    let result = extract_evm_fulfillment_params(&tx);

    assert!(
        result.is_err(),
        "Extraction should fail when calldata is too short"
    );
    let error_msg = result.unwrap_err().to_string();
    assert!(error_msg.contains("Insufficient") || error_msg.contains("length"));
}

/// Test that extract_evm_fulfillment_params rejects amounts exceeding u64::MAX
///
/// What is tested: Attempting to extract parameters from an EVM transaction with an amount
/// that exceeds u64::MAX should fail with a clear error about Move contract limitation.
///
/// Why: Move contracts only support u64 for amounts, so EVM amounts must not exceed u64::MAX.
/// This test verifies the overflow validation we added.
#[test]
fn test_extract_evm_fulfillment_params_amount_exceeds_u64_max() {
    // u64::MAX = 18446744073709551615 (0xffffffffffffffff)
    // Use u64::MAX + 1 = 18446744073709551616 (0x10000000000000000)
    // Padded to 32 bytes (64 hex chars): 0000000000000000000000000000000000000000000000010000000000000000
    let amount_exceeding_u64_max =
        "0000000000000000000000000000000000000000000000010000000000000000"; // u64::MAX + 1, padded to 32 bytes

    let calldata = format!(
        "a9059cbb000000000000000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa{}{}",
        amount_exceeding_u64_max,
        "1111111111111111111111111111111111111111111111111111111111111111" // intent_id
    );

    let tx = EvmTransaction {
        input: format!("0x{}", calldata),
        ..create_base_evm_transaction()
    };

    let result = extract_evm_fulfillment_params(&tx);

    assert!(
        result.is_err(),
        "Extraction should fail when amount exceeds u64::MAX"
    );
    let error_msg = result.unwrap_err().to_string();
    assert!(
        error_msg.contains("exceeds") && error_msg.contains("u64::MAX"),
        "Error message should mention exceeding u64::MAX. Got: {}",
        error_msg
    );
    assert!(
        error_msg.contains("Move contract") || error_msg.contains("Move contracts"),
        "Error message should mention Move contract limitation. Got: {}",
        error_msg
    );
}

/// Test that extract_evm_fulfillment_params accepts amounts equal to u64::MAX
///
/// What is tested: Extracting parameters from an EVM transaction with an amount
/// exactly equal to u64::MAX should succeed.
///
/// Why: Verify that the maximum allowed value (u64::MAX) is accepted.
#[test]
fn test_extract_evm_fulfillment_params_amount_equals_u64_max() {
    // u64::MAX = 18446744073709551615 (0xffffffffffffffff)
    // Padded to 32 bytes (64 hex chars): 000000000000000000000000000000000000000000000000ffffffffffffffff
    let amount_u64_max = "000000000000000000000000000000000000000000000000ffffffffffffffff"; // u64::MAX, padded to 32 bytes

    let calldata = format!(
        "a9059cbb000000000000000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa{}{}",
        amount_u64_max,
        "1111111111111111111111111111111111111111111111111111111111111111" // intent_id
    );

    let tx = EvmTransaction {
        input: format!("0x{}", calldata),
        ..create_base_evm_transaction()
    };

    let result = extract_evm_fulfillment_params(&tx);

    assert!(
        result.is_ok(),
        "Extraction should succeed when amount equals u64::MAX"
    );
    let params = result.unwrap();
    assert_eq!(
        params.amount,
        u64::MAX,
        "Extracted amount should equal u64::MAX"
    );
}

/// Test that extract_evm_fulfillment_params accepts large but valid u64 amounts
///
/// What is tested: Extracting parameters from an EVM transaction with a large
/// but valid u64 amount (close to but not exceeding u64::MAX) should succeed.
///
/// Why: Verify that large but valid amounts are handled correctly.
#[test]
fn test_extract_evm_fulfillment_params_large_valid_amount() {
    // Use a large but valid u64 value: 1000000000000000000 (10^18, 1 ETH in wei)
    // This is well within u64::MAX but tests large number handling
    let large_amount = "0000000000000000000000000000000000000000000000000de0b6b3a7640000"; // 1000000000000000000, padded to 32 bytes (64 hex chars)

    let calldata = format!(
        "a9059cbb000000000000000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa{}{}",
        large_amount,
        "1111111111111111111111111111111111111111111111111111111111111111" // intent_id
    );

    let tx = EvmTransaction {
        input: format!("0x{}", calldata),
        ..create_base_evm_transaction()
    };

    let result = extract_evm_fulfillment_params(&tx);

    assert!(
        result.is_ok(),
        "Extraction should succeed for large but valid u64 amount"
    );
    let params = result.unwrap();
    assert_eq!(
        params.amount, 1000000000000000000u64,
        "Extracted amount should match the large value"
    );
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Helper to create a mock SolverRegistry resource response with EVM address
fn create_solver_registry_resource_with_evm_address(
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

/// Setup a mock server that responds to get_resources calls with SolverRegistry
async fn setup_mock_server_with_registry(
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
    let solver_address = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let evm_address = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let registry_address = "0x1";

    let (_mock_server, validator) =
        setup_mock_server_with_registry(registry_address, solver_address, Some(evm_address)).await;

    let request_intent = RequestIntentEvent {
        desired_amount: 25000000, // For outflow request intents, validation uses desired_amount (amount desired on connected chain)
        reserved_solver: Some(solver_address.to_string()),
        ..create_base_request_intent_evm()
    };

    let tx_params = FulfillmentTransactionParams {
        amount: 25000000,
        solver: evm_address.to_string(),
        ..create_base_fulfillment_transaction_params_evm()
    };

    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, true).await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        validation_result.valid,
        "Validation should pass when all parameters match and solver is registered. Message: {}",
        validation_result.message
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
    let config = build_test_config_with_evm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let request_intent = create_base_request_intent_evm();
    let tx_params = FulfillmentTransactionParams {
        intent_id: request_intent.intent_id.clone(),
        amount: request_intent.desired_amount,
        ..create_base_fulfillment_transaction_params_evm()
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
    let config = build_test_config_with_evm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let request_intent = create_base_request_intent_evm();
    let tx_params = FulfillmentTransactionParams {
        intent_id: "0xwrong_intent_id".to_string(), // Different intent_id
        amount: request_intent.desired_amount,
        ..create_base_fulfillment_transaction_params_evm()
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
    let config = build_test_config_with_evm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let request_intent = RequestIntentEvent {
        ..create_base_request_intent_evm()
    };

    let tx_params = FulfillmentTransactionParams {
        recipient: "0xdddddddddddddddddddddddddddddddddddddddd".to_string(), // Different recipient (EVM address format)
        amount: request_intent.desired_amount,
        ..create_base_fulfillment_transaction_params_evm()
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
    let config = build_test_config_with_evm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    let request_intent = RequestIntentEvent {
        desired_amount: 1000,
        ..create_base_request_intent_evm()
    };

    let tx_params = FulfillmentTransactionParams {
        amount: 500, // Different amount
        ..create_base_fulfillment_transaction_params_evm()
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

/// Test that validate_outflow_fulfillment fails when solver doesn't match reserved solver
///
/// What is tested: Validating an outflow fulfillment transaction where the transaction's solver
/// doesn't match the request intent's reserved solver should result in validation failure.
///
/// Why: Verify that only the authorized solver can fulfill the intent.
#[tokio::test]
async fn test_validate_outflow_fulfillment_fails_on_solver_mismatch() {
    let solver_address = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let registered_evm_address = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let different_solver = "0xcccccccccccccccccccccccccccccccccccccccc";
    let registry_address = "0x1";

    let (_mock_server, validator) = setup_mock_server_with_registry(
        registry_address,
        solver_address,
        Some(registered_evm_address),
    )
    .await;

    let request_intent = RequestIntentEvent {
        desired_amount: 1000, // Set desired_amount to avoid validation failure on amount check
        reserved_solver: Some(solver_address.to_string()),
        ..create_base_request_intent_evm()
    };

    let tx_params = FulfillmentTransactionParams {
        amount: request_intent.desired_amount,
        solver: different_solver.to_string(), // Different solver (EVM address format)
        ..create_base_fulfillment_transaction_params_evm()
    };

    let result = validate_outflow_fulfillment(&validator, &request_intent, &tx_params, true).await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    if validation_result.valid {
        panic!(
            "Validation should fail when solver doesn't match. Message: {}",
            validation_result.message
        );
    }
    assert!(
        !validation_result.valid,
        "Validation should fail when solver doesn't match"
    );
    assert!(
        validation_result.message.contains("solver")
            || validation_result.message.contains("Solver")
            || validation_result.message.contains("Transaction solver")
            || validation_result.message.contains("does not match")
            || validation_result.message.contains("reserved solver"),
        "Validation message should mention solver mismatch. Got: {}",
        validation_result.message
    );
}
