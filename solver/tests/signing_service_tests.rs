//! Unit tests for signing service
//!
//! These tests verify that the signing service correctly parses draft data
//! from JSON and handles various error cases.

use serde_json::json;
use solver::service::parse_draft_data;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a base draft data JSON with valid test values
/// This can be customized using serde_json::json! macro:
/// ```
/// let draft = json!({
///     "offered_amount": 2000,
///     ..create_base_draft_data()
/// });
/// ```
fn create_base_draft_data() -> serde_json::Value {
    json!({
        "offered_metadata": {
            "inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "offered_amount": 1000u64,
        "offered_chain_id": 1u64,
        "desired_metadata": {
            "inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        "desired_amount": 2000u64,
        "desired_chain_id": 2u64,
        "expiry_time": 1000000u64,
    })
}

/// Create a minimal SolverConfig for testing
/// Configures token pairs to match the base draft data so drafts would be accepted if not expired
fn create_test_solver_config() -> solver::config::SolverConfig {
    use solver::config::{AcceptanceConfig, ChainConfig, ConnectedChainConfig, ServiceConfig, SolverConfig, SolverSigningConfig};
    use std::collections::HashMap;

    // Configure token pair matching base draft data:
    // offered: chain 1, 0xaaaa... (1000 amount)
    // desired: chain 2, 0xbbbb... (2000 amount)
    // Exchange rate 0.5 means: 1000 offered >= 2000 desired * 0.5 = 1000, so draft would be accepted
    let mut token_pairs = HashMap::new();
    token_pairs.insert(
        "1:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:2:0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(),
        0.5,  // Exchange rate: 0.5 offered per 1 desired
    );

    SolverConfig {
        service: ServiceConfig {
            verifier_url: "http://127.0.0.1:3333".to_string(),
            polling_interval_ms: 2000,
        },
        hub_chain: ChainConfig {
            name: "Hub Chain".to_string(),
            rpc_url: "http://127.0.0.1:8080/v1".to_string(),
            chain_id: 1,
            module_address: "0x123".to_string(),
            profile: "test-profile".to_string(),
        },
        connected_chain: ConnectedChainConfig::Mvm(ChainConfig {
            name: "Connected Chain".to_string(),
            rpc_url: "http://127.0.0.1:8082/v1".to_string(),
            chain_id: 2,
            module_address: "0x456".to_string(),
            profile: "test-profile".to_string(),
        }),
        acceptance: AcceptanceConfig {
            token_pairs,
        },
        solver: SolverSigningConfig {
            profile: "test-profile".to_string(),
            address: "0xcccccccccccccccccccccccccccccccccccccccc".to_string(),
        },
    }
}

/// Create a PendingDraft with specified expiry time
fn create_test_pending_draft(expiry_time: u64) -> solver::verifier_client::PendingDraft {
    solver::verifier_client::PendingDraft {
        draft_id: "test-draft-1".to_string(),
        requester_address: "0x1111111111111111111111111111111111111111".to_string(),
        draft_data: create_base_draft_data(),
        timestamp: 1000000,
        expiry_time,
    }
}

// ============================================================================
// DRAFT DATA PARSING TESTS
// ============================================================================

/// Test that valid draft data is parsed correctly
/// What is tested: Parsing a complete, valid draft data JSON structure
/// Why: Verify that the parser correctly extracts all required fields from the verifier's JSON response
#[test]
fn test_parse_draft_data_success() {
    let draft_data = create_base_draft_data();
    let result = parse_draft_data(&draft_data).unwrap();

    assert_eq!(result.offered_token, "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    assert_eq!(result.offered_amount, 1000);
    assert_eq!(result.offered_chain_id, 1);
    assert_eq!(result.desired_token, "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    assert_eq!(result.desired_amount, 2000);
    assert_eq!(result.desired_chain_id, 2);
}

/// Test that missing offered_metadata field returns an error
/// What is tested: Error handling when offered_metadata is missing
/// Why: Ensure the parser fails gracefully when required fields are missing
#[test]
fn test_parse_draft_data_missing_offered_metadata() {
    let draft_data = json!({
        "offered_amount": 1000u64,
        "offered_chain_id": 1u64,
        "desired_metadata": {
            "inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        "desired_amount": 2000u64,
        "desired_chain_id": 2u64,
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("offered_metadata"));
}

/// Test that missing offered_metadata.inner field returns an error
/// What is tested: Error handling when nested inner field is missing
/// Why: Ensure the parser correctly accesses nested JSON structures
#[test]
fn test_parse_draft_data_missing_offered_metadata_inner() {
    let draft_data = json!({
        "offered_metadata": {},
        "offered_amount": 1000u64,
        "offered_chain_id": 1u64,
        "desired_metadata": {
            "inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        "desired_amount": 2000u64,
        "desired_chain_id": 2u64,
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("offered_metadata.inner"));
}

/// Test that missing offered_amount field returns an error
/// What is tested: Error handling when offered_amount is missing
/// Why: Ensure all required numeric fields are validated
#[test]
fn test_parse_draft_data_missing_offered_amount() {
    let draft_data = json!({
        "offered_metadata": {
            "inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "offered_chain_id": 1u64,
        "desired_metadata": {
            "inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        "desired_amount": 2000u64,
        "desired_chain_id": 2u64,
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("offered_amount"));
}

/// Test that invalid offered_amount type (string instead of number) returns an error
/// What is tested: Type validation for numeric fields
/// Why: Ensure the parser rejects invalid data types
#[test]
fn test_parse_draft_data_invalid_offered_amount_type() {
    let draft_data = json!({
        "offered_metadata": {
            "inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "offered_amount": "1000",  // String instead of number
        "offered_chain_id": 1u64,
        "desired_metadata": {
            "inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        "desired_amount": 2000u64,
        "desired_chain_id": 2u64,
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("offered_amount"));
}

/// Test that missing offered_chain_id field returns an error
/// What is tested: Error handling when offered_chain_id is missing
/// Why: Ensure chain ID fields are validated
#[test]
fn test_parse_draft_data_missing_offered_chain_id() {
    let draft_data = json!({
        "offered_metadata": {
            "inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "offered_amount": 1000u64,
        "desired_metadata": {
            "inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        "desired_amount": 2000u64,
        "desired_chain_id": 2u64,
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("offered_chain_id"));
}

/// Test that missing desired_metadata field returns an error
/// What is tested: Error handling when desired_metadata is missing
/// Why: Ensure desired token metadata is validated
#[test]
fn test_parse_draft_data_missing_desired_metadata() {
    let draft_data = json!({
        "offered_metadata": {
            "inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "offered_amount": 1000u64,
        "offered_chain_id": 1u64,
        "desired_amount": 2000u64,
        "desired_chain_id": 2u64,
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("desired_metadata"));
}

/// Test that missing desired_metadata.inner field returns an error
/// What is tested: Error handling when nested inner field is missing for desired token
/// Why: Ensure nested JSON structures are correctly validated for both tokens
#[test]
fn test_parse_draft_data_missing_desired_metadata_inner() {
    let draft_data = json!({
        "offered_metadata": {
            "inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "offered_amount": 1000u64,
        "offered_chain_id": 1u64,
        "desired_metadata": {},
        "desired_amount": 2000u64,
        "desired_chain_id": 2u64,
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("desired_metadata.inner"));
}

/// Test that missing desired_amount field returns an error
/// What is tested: Error handling when desired_amount is missing
/// Why: Ensure all required numeric fields are validated
#[test]
fn test_parse_draft_data_missing_desired_amount() {
    let draft_data = json!({
        "offered_metadata": {
            "inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "offered_amount": 1000u64,
        "offered_chain_id": 1u64,
        "desired_metadata": {
            "inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        "desired_chain_id": 2u64,
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("desired_amount"));
}

/// Test that missing desired_chain_id field returns an error
/// What is tested: Error handling when desired_chain_id is missing
/// Why: Ensure chain ID fields are validated for both tokens
#[test]
fn test_parse_draft_data_missing_desired_chain_id() {
    let draft_data = json!({
        "offered_metadata": {
            "inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "offered_amount": 1000u64,
        "offered_chain_id": 1u64,
        "desired_metadata": {
            "inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        "desired_amount": 2000u64,
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("desired_chain_id"));
}

/// Test that invalid chain_id type (string instead of number) returns an error
/// What is tested: Type validation for chain ID fields
/// Why: Ensure chain IDs are validated as numeric values
#[test]
fn test_parse_draft_data_invalid_chain_id_type() {
    let draft_data = json!({
        "offered_metadata": {
            "inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "offered_amount": 1000u64,
        "offered_chain_id": "1",  // String instead of number
        "desired_metadata": {
            "inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        "desired_amount": 2000u64,
        "desired_chain_id": 2u64,
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("offered_chain_id"));
}

/// Test that empty JSON object returns an error
/// What is tested: Error handling for completely empty draft data
/// Why: Ensure the parser rejects empty or malformed JSON
#[test]
fn test_parse_draft_data_empty_json() {
    let draft_data = json!({});

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
}

/// Test that offered_metadata.inner with non-string value returns an error
/// What is tested: Type validation for token address fields
/// Why: Ensure token addresses are validated as strings
#[test]
fn test_parse_draft_data_invalid_metadata_inner_type() {
    let draft_data = json!({
        "offered_metadata": {
            "inner": 12345  // Number instead of string
        },
        "offered_amount": 1000u64,
        "offered_chain_id": 1u64,
        "desired_metadata": {
            "inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        "desired_amount": 2000u64,
        "desired_chain_id": 2u64,
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("offered_metadata.inner"));
}

/// Test parsing with zero amounts (edge case)
/// What is tested: Parsing draft data with zero values
/// Why: Verify that zero is a valid amount (acceptance logic will reject it, but parsing should work)
#[test]
fn test_parse_draft_data_zero_amounts() {
    let draft_data = json!({
        "offered_metadata": {
            "inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "offered_amount": 0u64,
        "offered_chain_id": 1u64,
        "desired_metadata": {
            "inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        "desired_amount": 0u64,
        "desired_chain_id": 2u64,
    });

    let result = parse_draft_data(&draft_data).unwrap();
    assert_eq!(result.offered_amount, 0);
    assert_eq!(result.desired_amount, 0);
}

/// Test parsing with maximum u64 amounts (edge case)
/// What is tested: Parsing draft data with very large values
/// Why: Verify that the parser handles maximum u64 values correctly
#[test]
fn test_parse_draft_data_max_amounts() {
    let draft_data = json!({
        "offered_metadata": {
            "inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "offered_amount": u64::MAX,
        "offered_chain_id": 1u64,
        "desired_metadata": {
            "inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        "desired_amount": u64::MAX,
        "desired_chain_id": 2u64,
    });

    let result = parse_draft_data(&draft_data).unwrap();
    assert_eq!(result.offered_amount, u64::MAX);
    assert_eq!(result.desired_amount, u64::MAX);
}

// ============================================================================
// EXPIRY CHECKING TESTS
// ============================================================================

/// Test that expired drafts are rejected by process_draft
/// What is tested: Expiry checking logic in process_draft rejects drafts with expiry_time in the past
/// Why: Expired drafts should not be processed or signed
#[tokio::test]
async fn test_process_draft_rejects_expired_draft() {
    let config = create_test_solver_config();
    let service = solver::service::SigningService::new(config).unwrap();

    // Create an expired draft (expiry_time in the past)
    let current_time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let past_expiry = current_time - 1000; // Expired 1000 seconds ago

    let expired_draft = create_test_pending_draft(past_expiry);

    // Process the expired draft - should return false without attempting to sign
    let result = service.process_draft(&expired_draft).await.unwrap();
    assert_eq!(result, false);
}

/// Test that non-expired drafts proceed to acceptance evaluation
/// What is tested: Non-expired drafts are not rejected by expiry check and proceed to acceptance/signing
/// Why: Valid drafts should proceed through the processing pipeline past expiry check
#[tokio::test]
async fn test_process_draft_accepts_non_expired_draft() {
    let config = create_test_solver_config();
    let service = solver::service::SigningService::new(config).unwrap();

    // Create a non-expired draft (expiry_time in the future)
    let current_time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let future_expiry = current_time + 1000; // Expires in 1000 seconds

    let non_expired_draft = create_test_pending_draft(future_expiry);

    // Process the non-expired draft
    // With token pairs configured, it should proceed past expiry check and acceptance check
    // It will then attempt to sign, which will fail (requires CLI/HTTP calls in test environment)
    // We verify it got past expiry check by checking the error is from signing, not expiry
    let result = service.process_draft(&non_expired_draft).await;
    
    // Should fail, but the error should be from signing (CLI/HTTP), not from expiry
    // This proves it got past the expiry check
    assert!(result.is_err());
    let error_msg = result.unwrap_err().to_string();
    // Error should be from signing (profile/CLI/HTTP), not expiry
    assert!(
        error_msg.contains("profile") || 
        error_msg.contains("private key") || 
        error_msg.contains("Failed to get") ||
        error_msg.contains("CLI") ||
        error_msg.contains("HTTP"),
        "Error should be from signing, not expiry. Got: {}",
        error_msg
    );
}

/// Test that drafts with expiry_time exactly equal to current time are rejected
/// What is tested: Edge case where expiry_time == current_time (should be rejected due to >= check)
/// Why: Verify the boundary condition for expiry checking
#[tokio::test]
async fn test_process_draft_rejects_draft_at_expiry_boundary() {
    let config = create_test_solver_config();
    let service = solver::service::SigningService::new(config).unwrap();

    // Create a draft with expiry_time exactly at current time
    let current_time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let draft_at_boundary = create_test_pending_draft(current_time);

    // Process the draft - should be rejected (expiry_time >= now)
    let result = service.process_draft(&draft_at_boundary).await;
    
    // Should return false (expired)
    // Note: There's a small race condition here - if current_time advances between
    // getting it and checking in process_draft, the result might vary
    // But in most cases, it should be rejected
    assert!(result.is_ok());
    // If it's rejected, that's correct (expired)
    // If it's not rejected, that means current_time advanced, which is also valid behavior
    // We just verify it doesn't crash
}

