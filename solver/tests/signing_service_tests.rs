//! Unit tests for signing service
//!
//! These tests verify that the signing service correctly parses draft data
//! from JSON and handles various error cases.

#[path = "helpers.rs"]
mod test_helpers;
use test_helpers::{
    create_default_solver_config, DUMMY_EXPIRY, DUMMY_INTENT_ID, DUMMY_REQUESTER_ADDR_EVM,
    DUMMY_TOKEN_ADDR_MVM_CON, DUMMY_TOKEN_ADDR_MVM_HUB,
};

use serde_json::json;
use solver::service::parse_draft_data;
use std::sync::Arc;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a default draft data JSON with valid test values
fn create_default_draft_data() -> serde_json::Value {
    json!({
        "intent_id": DUMMY_INTENT_ID,
        "offered_metadata": DUMMY_TOKEN_ADDR_MVM_HUB,
        "offered_amount": "1000",
        "offered_chain_id": "1",
        "desired_metadata": DUMMY_TOKEN_ADDR_MVM_CON,
        "desired_amount": "2000",
        "desired_chain_id": "2",
        "expiry_time": DUMMY_EXPIRY.to_string(),
    })
}

/// Create a minimal SolverConfig for testing
/// Configures token pairs to match the default draft data so drafts would be accepted if not expired
fn create_test_solver_config() -> solver::config::SolverConfig {
    use solver::config::{AcceptanceConfig, SolverConfig};
    use std::collections::HashMap;

    let mut token_pairs = HashMap::new();
    token_pairs.insert(
        format!("1:{}:2:{}", DUMMY_TOKEN_ADDR_MVM_HUB, DUMMY_TOKEN_ADDR_MVM_CON),
        0.5,
    );

    SolverConfig {
        acceptance: AcceptanceConfig {
            token_pairs,
        },
        ..create_default_solver_config()
    }
}

/// Create a PendingDraft with specified expiry time
fn create_test_pending_draft(expiry_time: u64) -> solver::verifier_client::PendingDraft {
    solver::verifier_client::PendingDraft {
        draft_id: "test-draft-1".to_string(),
        requester_addr: DUMMY_REQUESTER_ADDR_EVM.to_string(),
        draft_data: create_default_draft_data(),
        timestamp: DUMMY_EXPIRY,
        expiry_time,
    }
}

// ============================================================================
// DRAFT DATA PARSING TESTS
// ============================================================================

/// What is tested: parse_draft_data() correctly parses valid draft data JSON
/// Why: Ensure the parser extracts all required fields correctly from well-formed input
#[test]
fn test_parse_draft_data_success() {
    let draft_data = create_default_draft_data();
    let result = parse_draft_data(&draft_data).unwrap();

    assert_eq!(result.offered_token, DUMMY_TOKEN_ADDR_MVM_HUB);
    assert_eq!(result.offered_amount, 1000);
    assert_eq!(result.offered_chain_id, 1);
    assert_eq!(result.desired_token, DUMMY_TOKEN_ADDR_MVM_CON);
    assert_eq!(result.desired_amount, 2000);
    assert_eq!(result.desired_chain_id, 2);
}

/// What is tested: parse_draft_data() returns error when offered_metadata field is missing
/// Why: Ensure all required fields are validated and missing fields produce clear errors
#[test]
fn test_parse_draft_data_missing_offered_metadata() {
    let draft_data = json!({
        "intent_id": DUMMY_INTENT_ID,
        "offered_amount": "1000",
        "offered_chain_id": "1",
        "desired_metadata": DUMMY_TOKEN_ADDR_MVM_CON,
        "desired_amount": "2000",
        "desired_chain_id": "2",
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("offered_metadata"));
}

/// What is tested: parse_draft_data() returns error when offered_metadata is not a string
/// Why: Ensure type validation catches invalid data types for string fields
#[test]
fn test_parse_draft_data_invalid_offered_metadata_type() {
    let draft_data = json!({
        "intent_id": DUMMY_INTENT_ID,
        "offered_metadata": 12345, // Test-specific: invalid type (number instead of string) to test validation
        "offered_amount": "1000",
        "offered_chain_id": "1",
        "desired_metadata": DUMMY_TOKEN_ADDR_MVM_CON,
        "desired_amount": "2000",
        "desired_chain_id": "2",
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("offered_metadata"));
}

/// What is tested: parse_draft_data() returns error when offered_amount field is missing
/// Why: Ensure all required numeric fields are validated
#[test]
fn test_parse_draft_data_missing_offered_amount() {
    let draft_data = json!({
        "intent_id": DUMMY_INTENT_ID,
        "offered_metadata": DUMMY_TOKEN_ADDR_MVM_HUB,
        "offered_chain_id": "1",
        "desired_metadata": DUMMY_TOKEN_ADDR_MVM_CON,
        "desired_amount": "2000",
        "desired_chain_id": "2",
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("offered_amount"));
}

/// What is tested: parse_draft_data() returns error when offered_amount is not a valid number
/// Why: Ensure numeric validation catches invalid values that cannot be parsed
#[test]
fn test_parse_draft_data_invalid_offered_amount() {
    let draft_data = json!({
        "intent_id": DUMMY_INTENT_ID,
        "offered_metadata": DUMMY_TOKEN_ADDR_MVM_HUB,
        "offered_amount": "not_a_number", // Test-specific: invalid number string to test validation
        "offered_chain_id": "1",
        "desired_metadata": DUMMY_TOKEN_ADDR_MVM_CON,
        "desired_amount": "2000",
        "desired_chain_id": "2",
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("offered_amount"));
}

/// What is tested: parse_draft_data() returns error when offered_chain_id field is missing
/// Why: Ensure chain ID validation catches missing chain identifiers
#[test]
fn test_parse_draft_data_missing_offered_chain_id() {
    let draft_data = json!({
        "intent_id": DUMMY_INTENT_ID,
        "offered_metadata": DUMMY_TOKEN_ADDR_MVM_HUB,
        "offered_amount": "1000",
        "desired_metadata": DUMMY_TOKEN_ADDR_MVM_CON,
        "desired_amount": "2000",
        "desired_chain_id": "2",
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("offered_chain_id"));
}

/// What is tested: parse_draft_data() returns error when desired_metadata field is missing
/// Why: Ensure desired token metadata is required for intent processing
#[test]
fn test_parse_draft_data_missing_desired_metadata() {
    let draft_data = json!({
        "intent_id": DUMMY_INTENT_ID,
        "offered_metadata": DUMMY_TOKEN_ADDR_MVM_HUB,
        "offered_amount": "1000",
        "offered_chain_id": "1",
        "desired_amount": "2000",
        "desired_chain_id": "2",
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("desired_metadata"));
}

/// What is tested: parse_draft_data() returns error when desired_amount field is missing
/// Why: Ensure desired amount is required for exchange rate validation
#[test]
fn test_parse_draft_data_missing_desired_amount() {
    let draft_data = json!({
        "intent_id": DUMMY_INTENT_ID,
        "offered_metadata": DUMMY_TOKEN_ADDR_MVM_HUB,
        "offered_amount": "1000",
        "offered_chain_id": "1",
        "desired_metadata": DUMMY_TOKEN_ADDR_MVM_CON,
        "desired_chain_id": "2",
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("desired_amount"));
}

/// What is tested: parse_draft_data() returns error when desired_chain_id field is missing
/// Why: Ensure destination chain is required for cross-chain intent routing
#[test]
fn test_parse_draft_data_missing_desired_chain_id() {
    let draft_data = json!({
        "intent_id": DUMMY_INTENT_ID,
        "offered_metadata": DUMMY_TOKEN_ADDR_MVM_HUB,
        "offered_amount": "1000",
        "offered_chain_id": "1",
        "desired_metadata": DUMMY_TOKEN_ADDR_MVM_CON,
        "desired_amount": "2000",
    });

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("desired_chain_id"));
}

/// What is tested: parse_draft_data() returns error for empty JSON object
/// Why: Ensure completely invalid input is rejected with appropriate error
#[test]
fn test_parse_draft_data_empty_json() {
    let draft_data = json!({});

    let result = parse_draft_data(&draft_data);
    assert!(result.is_err());
}

/// What is tested: parse_draft_data() accepts zero amounts
/// Why: Ensure edge case of zero amounts is handled (validation of zero may be done elsewhere)
#[test]
fn test_parse_draft_data_zero_amounts() {
    let draft_data = json!({
        "intent_id": DUMMY_INTENT_ID,
        "offered_metadata": DUMMY_TOKEN_ADDR_MVM_HUB,
        "offered_amount": "0",
        "offered_chain_id": "1",
        "desired_metadata": DUMMY_TOKEN_ADDR_MVM_CON,
        "desired_amount": "0",
        "desired_chain_id": "2",
    });

    let result = parse_draft_data(&draft_data).unwrap();
    assert_eq!(result.offered_amount, 0);
    assert_eq!(result.desired_amount, 0);
}

/// What is tested: parse_draft_data() accepts maximum u64 amounts
/// Why: Ensure large amounts at u64 boundary are parsed correctly without overflow
#[test]
fn test_parse_draft_data_max_amounts() {
    let draft_data = json!({
        "intent_id": DUMMY_INTENT_ID,
        "offered_metadata": DUMMY_TOKEN_ADDR_MVM_HUB,
        "offered_amount": u64::MAX.to_string(),
        "offered_chain_id": "1",
        "desired_metadata": DUMMY_TOKEN_ADDR_MVM_CON,
        "desired_amount": u64::MAX.to_string(),
        "desired_chain_id": "2",
    });

    let result = parse_draft_data(&draft_data).unwrap();
    assert_eq!(result.offered_amount, u64::MAX);
    assert_eq!(result.desired_amount, u64::MAX);
}

// ============================================================================
// EXPIRY CHECKING TESTS
// ============================================================================

/// What is tested: process_draft() rejects drafts that have already expired
/// Why: Ensure solver does not sign intents that cannot be fulfilled before expiry
#[tokio::test]
async fn test_process_draft_rejects_expired_draft() {
    let config = create_test_solver_config();
    let tracker = Arc::new(solver::service::IntentTracker::new(&config).unwrap());
    let service = solver::service::SigningService::new(config, tracker).unwrap();

    let current_time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let past_expiry = current_time - 1000;

    let expired_draft = create_test_pending_draft(past_expiry);

    let result = service.process_draft(&expired_draft).await.unwrap();
    assert_eq!(result, false);
}

/// What is tested: process_draft() proceeds with non-expired drafts (may fail on signing)
/// Why: Ensure valid drafts are not rejected due to expiry check and proceed to signing
#[tokio::test]
async fn test_process_draft_accepts_non_expired_draft() {
    let config = create_test_solver_config();
    let tracker = Arc::new(solver::service::IntentTracker::new(&config).unwrap());
    let service = solver::service::SigningService::new(config, tracker).unwrap();

    let current_time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let future_expiry = current_time + 1000;

    let non_expired_draft = create_test_pending_draft(future_expiry);

    let result = service.process_draft(&non_expired_draft).await;
    
    // Should fail, but from signing (CLI/HTTP), not expiry
    assert!(result.is_err());
    let error_msg = result.unwrap_err().to_string();
    assert!(
        error_msg.contains("profile") || 
        error_msg.contains("private key") || 
        error_msg.contains("Failed to get") ||
        error_msg.contains("CLI") ||
        error_msg.contains("HTTP") ||
        error_msg.contains("Signing failed"),
        "Error should be from signing, not expiry. Got: {}",
        error_msg
    );
}

/// What is tested: process_draft() handles drafts at expiry boundary
/// Why: Ensure drafts exactly at current time are handled correctly (edge case)
#[tokio::test]
async fn test_process_draft_rejects_draft_at_expiry_boundary() {
    let config = create_test_solver_config();
    let tracker = Arc::new(solver::service::IntentTracker::new(&config).unwrap());
    let service = solver::service::SigningService::new(config, tracker).unwrap();

    let current_time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let draft_at_boundary = create_test_pending_draft(current_time);

    let result = service.process_draft(&draft_at_boundary).await;
    assert!(result.is_ok());
}
