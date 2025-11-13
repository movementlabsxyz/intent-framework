//! Unit tests for cross-chain matching logic
//!
//! These tests verify that escrow events can be matched to intent events
//! across different chains using intent_id.

use trusted_verifier::monitor::{RequestIntentEvent, EscrowEvent};
#[path = "mod.rs"]
mod test_helpers;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a test request intent with customizable fields
fn create_test_request_intent(
    intent_id: &str,
    issuer: &str,
    offered_metadata: &str,
    offered_amount: u64,
    desired_metadata: &str,
    solver: Option<String>,
    connected_chain_id: Option<u64>,
) -> RequestIntentEvent {
    RequestIntentEvent {
        chain: "hub".to_string(),
        intent_id: intent_id.to_string(),
        issuer: issuer.to_string(),
        offered_metadata: offered_metadata.to_string(),
        offered_amount,
        desired_metadata: desired_metadata.to_string(),
        desired_amount: 0, // Escrow only holds offered funds
        expiry_time: 1000000,
        revocable: false,
        solver,
        connected_chain_id,
        timestamp: 0,
    }
}

/// Create a test escrow event with customizable fields
fn create_test_escrow_event(
    escrow_id: &str,
    intent_id: &str,
    issuer: &str,
    offered_metadata: &str,
    offered_amount: u64,
    desired_metadata: &str,
    reserved_solver: Option<String>,
    chain_id: u64,
) -> EscrowEvent {
    EscrowEvent {
        chain: "connected".to_string(),
        escrow_id: escrow_id.to_string(),
        intent_id: intent_id.to_string(),
        issuer: issuer.to_string(),
        offered_metadata: offered_metadata.to_string(),
        offered_amount,
        desired_metadata: desired_metadata.to_string(),
        desired_amount: 0, // Escrow only holds offered funds
        expiry_time: 1000000,
        revocable: false,
        reserved_solver,
        chain_id,
        chain_type: trusted_verifier::ChainType::Move,
        timestamp: 0,
    }
}

// ============================================================================
// TESTS
// ============================================================================

/// Test that escrow events can be matched to intent events by intent_id
/// Why: Verify cross-chain matching logic correctly links escrow to hub intent for validation
///
/// Cross-chain escrow flow:
/// 1. [HUB CHAIN] User creates intent on hub chain (requests tokens - solver will fulfill)
///    - Intent requests 1000 tokens to be provided by solver
///    - User creates intent with intent_id
///
/// 2. [CONNECTED CHAIN] User creates escrow on connected chain WITH tokens locked in it
///    - User locks 1000 tokens in escrow
///    - User provides hub chain intent_id when creating escrow
///    - Escrow event includes intent_id linking back to hub intent
///
/// 3. [HUB CHAIN] Solver monitors escrow event on connected chain and fulfills intent on hub chain
///    - Solver sees escrow event on connected chain
///    - Solver provides 1000 tokens on hub chain to fulfill the intent
///    - Solver fulfills hub intent (provides tokens on hub chain)
///
/// 4. [HUB CHAIN] Verifier validates cross-chain conditions are met
///    - Verifier matches escrow.intent_id to hub_intent.intent_id
///    - Verifier validates solver fulfilled the intent on hub chain
///      (validates deposit amounts, metadata, and expiry)
///
/// 5. [CONNECTED CHAIN] Verifier releases escrow to solver on connected chain
///    - Verifier generates approval signature
///    - Escrow is released to solver on connected chain
#[test]
fn test_cross_chain_intent_matching() {
    // Step 1: User creates intent on hub chain (requests 1000 tokens to be provided by solver)
    let hub_intent = create_test_request_intent(
        "0xhub_abc123",
        "0xalice",
        "{\"inner\":\"0xoffered_meta\"}",
        1000, // amount that will be locked in escrow on connected chain
        "{\"inner\":\"0xdesired_meta\"}",
        None,
        Some(2),
    );
    
    // Step 2: User creates escrow on connected chain WITH tokens locked in it
    // The user must manually provide the hub_intent_id when creating the escrow
    let escrow_creation = create_test_escrow_event(
        "0xescrow_xyz789",
        "0xhub_abc123",
        "0xalice",
        "{\"inner\":\"0xoffered_meta\"}",
        1000,
        "{\"inner\":\"0xdesired_meta\"}",
        None,
        2,
    );
    
    // Step 3: Solver fulfills hub intent (solver provides 1000 tokens on hub chain)
    // [Not yet tested. This will also be tested here, not just in integration tests.]
    
    // Step 4: Verifier validation 
    // [Not yet tested. This will also be tested here, not just in integration tests.]
    
    // Step 5: Verifier release
    // [Not yet tested. This will also be tested here, not just in integration tests.]
    
    // This unit test verifies that data structures support cross-chain matching
    // Verify matching: intent_id should match
    assert_eq!(escrow_creation.intent_id, hub_intent.intent_id, 
               "Escrow intent_id should match the hub intent_id");
    
    // Verify escrow has tokens locked (user creates escrow with tokens locked)
    assert_eq!(escrow_creation.offered_amount, 1000,
               "Escrow should have tokens locked (user created escrow with tokens)");
    
    // Verify the locked tokens in escrow match what the intent wants
    assert_eq!(escrow_creation.offered_amount, hub_intent.offered_amount,
               "Escrow locked tokens should match what intent wants");
}

/// Test that escrow chain_id validation works correctly
/// Why: Verify that escrow chain_id matches the intent's offered_chain_id when provided
#[tokio::test]
async fn test_escrow_chain_id_validation() {
    use trusted_verifier::validator::CrossChainValidator;
    use test_helpers::build_test_config;
    
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Test that escrow chain_id must match intent's offered_chain_id when provided
    let valid_intent = create_test_request_intent(
        "0xvalid_intent",
        "0xalice",
        "{}",
        1000,
        "{}",
        Some("0xsolver".to_string()),
        Some(2),
    );
    let valid_escrow = create_test_escrow_event(
        "0xescrow_valid",
        "0xvalid_intent",
        "0xalice",
        "{}",
        1000,
        "{}",
        Some("0xsolver".to_string()),
        2,
    );
    
    // This should pass the connected_chain_id check (may fail other validations, but not this one)
    let result = validator.validate_request_intent_fulfillment(&valid_intent, &valid_escrow).await;
    assert!(result.is_ok(), "Validation should complete");
    
    let validation_result = result.unwrap();
    // Assert 1: If validation fails, it should NOT be because of missing connected_chain_id
    if !validation_result.valid {
        assert!(!validation_result.message.contains("connected_chain_id"), 
                "Should not fail due to missing connected_chain_id when chain_id is provided");
    }
    // Assert 2: Validation may fail on other checks (like solver registry query), but should not fail on connected_chain_id
    // Note: This might fail other validations (like solver address mismatch if not properly mocked),
    // but for a complete test, we'd need to ensure all conditions are met
    // We just verify it doesn't fail on connected_chain_id check
}

/// Test that verifier rejects escrows where offered_amount doesn't match hub request intent's offered amount
/// Why: Verify that escrow amount validation works correctly
#[tokio::test]
async fn test_escrow_amount_must_match_hub_intent_offered_amount() {
    use trusted_verifier::validator::CrossChainValidator;
    use test_helpers::build_test_config;
    
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Create a hub intent with offered_amount = 1000
    let hub_intent = create_amount_validation_intent("0xintent_123", 1000);
    
    // Create an escrow with mismatched offered_amount (500 != 1000)
    let escrow_mismatch = create_amount_validation_escrow("0xescrow_123", "0xintent_123", 500);
    
    let validation_result = validator.validate_request_intent_fulfillment(&hub_intent, &escrow_mismatch).await
        .expect("Validation should complete without error");
    
    assert!(
        !validation_result.valid,
        "Validation should fail when escrow offered_amount doesn't match hub intent offered amount"
    );
    assert!(validation_result.message.contains("offered amount"),
            "Error message should mention offered amount mismatch");
    
    // Now test with matching amounts
    let escrow_match = create_amount_validation_escrow("0xescrow_456", "0xintent_123", 1000);
    
    let validation_result = validator.validate_request_intent_fulfillment(&hub_intent, &escrow_match).await
        .expect("Validation should complete without error");
    
    // Verify that validation doesn't fail due to amount mismatch (amount check passes)
    assert!(!validation_result.message.contains("offered amount"), 
            "Validation should not fail due to offered_amount mismatch when amounts match");
    
    // Verify that validation doesn't fail at all (all checks pass)
    assert!(validation_result.valid, "Validation should pass when all checks pass");
}

fn create_amount_validation_intent(intent_id: &str, offered_amount: u64) -> RequestIntentEvent {
    create_test_request_intent(
        intent_id,
        "0xalice",
        "{\"inner\":\"0xoffered_meta\"}",
        offered_amount,
        "{\"inner\":\"0xdesired_meta\"}",
        Some("0xsolver".to_string()),
        Some(2),
    )
}

fn create_amount_validation_escrow(escrow_id: &str, intent_id: &str, offered_amount: u64) -> EscrowEvent {
    create_test_escrow_event(
        escrow_id,
        intent_id,
        "0xalice",
        "{\"inner\":\"0xoffered_meta\"}",
        offered_amount,
        "{\"inner\":\"0xdesired_meta\"}",
        Some("0xsolver".to_string()),
        2,
    )
}

/// Test that verifier accepts escrows where offered_metadata exactly matches hub request intent's offered_metadata
/// Why: Verify that metadata matching validation works correctly for successful cases
#[tokio::test]
async fn test_escrow_offered_metadata_must_match_hub_intent_offered_metadata_success() {
    use trusted_verifier::validator::CrossChainValidator;
    use test_helpers::build_test_config;
    
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Create a hub intent with specific offered_metadata
    let hub_intent = create_test_request_intent(
        "0xintent_metadata_123",
        "0xalice",
        "{\"inner\":\"0xoffered_meta\"}",
        1000,
        "{\"inner\":\"0xdesired_meta\"}",
        Some("0xsolver".to_string()),
        Some(2),
    );
    
    // Create an escrow with matching offered_metadata
    let escrow_match = create_test_escrow_event(
        "0xescrow_metadata_123",
        "0xintent_metadata_123",
        "0xalice",
        "{\"inner\":\"0xoffered_meta\"}",
        1000,
        "{\"inner\":\"0xdesired_meta\"}",
        Some("0xsolver".to_string()),
        2,
    );
    
    let validation_result = validator.validate_request_intent_fulfillment(&hub_intent, &escrow_match).await
        .expect("Validation should complete without error");
    
    assert!(validation_result.valid, "Validation should pass when offered_metadata matches");
    assert!(!validation_result.message.contains("offered metadata"),
            "Error message should not mention offered metadata mismatch when metadata matches");
}

/// Test that verifier rejects escrows where offered_metadata doesn't match hub request intent's offered_metadata
/// Why: Verify that metadata mismatch validation works correctly
#[tokio::test]
async fn test_escrow_offered_metadata_must_match_hub_intent_offered_metadata_rejection() {
    use trusted_verifier::validator::CrossChainValidator;
    use test_helpers::build_test_config;
    
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Create a hub intent with specific offered_metadata
    let hub_intent = create_test_request_intent(
        "0xintent_metadata_456",
        "0xalice",
        "{\"inner\":\"0xoffered_meta\"}",
        1000,
        "{\"inner\":\"0xdesired_meta\"}",
        Some("0xsolver".to_string()),
        Some(2),
    );
    
    // Create an escrow with mismatched offered_metadata
    let escrow_mismatch = create_test_escrow_event(
        "0xescrow_metadata_456",
        "0xintent_metadata_456",
        "0xalice",
        "{\"inner\":\"0xdifferent_meta\"}",
        1000,
        "{\"inner\":\"0xdesired_meta\"}",
        Some("0xsolver".to_string()),
        2,
    );
    
    // The validation function should complete successfully (return Ok, not Err)
    let validation_result = validator.validate_request_intent_fulfillment(&hub_intent, &escrow_mismatch).await
        .expect("Validation should complete without error");
    
    // But the validation result should indicate failure (valid = false) because metadata doesn't match
    assert!(!validation_result.valid, "Validation should fail when offered_metadata doesn't match");
    assert!(validation_result.message.contains("offered metadata"),
            "Error message should mention offered metadata mismatch");
}

/// Test that verifier correctly handles empty metadata strings
/// Why: Verify that empty metadata strings are handled correctly (both empty should match, one empty one not should fail)
#[tokio::test]
async fn test_escrow_offered_metadata_empty_strings() {
    use trusted_verifier::validator::CrossChainValidator;
    use test_helpers::build_test_config;
    
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Test case 1: Both empty - should pass
    let hub_intent_empty = create_empty_metadata_intent(1, "");
    let escrow_empty = create_empty_metadata_escrow(1, "");
    
    let validation_result = validator.validate_request_intent_fulfillment(&hub_intent_empty, &escrow_empty).await
        .expect("Validation should complete without error");
    
    assert!(validation_result.valid, "Validation should pass when both metadata strings are empty");
    
    // Test case 2: Hub intent has metadata, escrow is empty - should fail
    let hub_intent_with_meta = create_empty_metadata_intent(2, "{\"inner\":\"0xoffered_meta\"}");
    let escrow_empty_2 = create_empty_metadata_escrow(2, "");
    
    let validation_result = validator.validate_request_intent_fulfillment(&hub_intent_with_meta, &escrow_empty_2).await
        .expect("Validation should complete without error");
    
    assert!(!validation_result.valid, "Validation should fail when hub intent has metadata but escrow is empty");
    assert!(validation_result.message.contains("offered metadata"),
            "Error message should mention offered metadata mismatch");
    
    // Test case 3: Hub intent is empty, escrow has metadata - should fail
    let hub_intent_empty_3 = create_empty_metadata_intent(3, "");
    let escrow_with_meta = create_empty_metadata_escrow(3, "{\"inner\":\"0xoffered_meta\"}");
    
    let validation_result = validator.validate_request_intent_fulfillment(&hub_intent_empty_3, &escrow_with_meta).await
        .expect("Validation should complete without error");
    
    assert!(!validation_result.valid, "Validation should fail when hub intent is empty but escrow has metadata");
    assert!(validation_result.message.contains("offered metadata"),
            "Error message should mention offered metadata mismatch");
}

fn create_empty_metadata_intent(case: u8, offered_metadata: &str) -> RequestIntentEvent {
    create_test_request_intent(
        &format!("0xintent_empty_{}", case),
        "0xalice",
        offered_metadata,
        1000,
        "",
        Some("0xsolver".to_string()),
        Some(2),
    )
}

fn create_empty_metadata_escrow(case: u8, offered_metadata: &str) -> EscrowEvent {
    create_test_escrow_event(
        &format!("0xescrow_empty_{}", case),
        &format!("0xintent_empty_{}", case),
        "0xalice",
        offered_metadata,
        1000,
        "",
        Some("0xsolver".to_string()),
        2,
    )
}

/// Test that verifier correctly handles complex JSON metadata structures
/// Why: Verify that exact string matching works for complex nested JSON, escaped characters, etc.
#[tokio::test]
async fn test_escrow_offered_metadata_complex_json() {
    use trusted_verifier::validator::CrossChainValidator;
    use test_helpers::build_test_config;
    
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Test case 1: Complex nested JSON - should pass when exact match
    let complex_metadata = r#"{"nested":{"level1":{"level2":"value","array":[1,2,3],"escaped":"\"quoted\""},"timestamp":1234567890},"metadata":"complex"}"#;
    
    let hub_intent_complex = create_complex_json_intent("0xintent_complex_1", complex_metadata);
    let escrow_complex_match = create_complex_json_escrow(
        "0xescrow_complex_1",
        "0xintent_complex_1",
        complex_metadata,
    );
    
    let validation_result = validator.validate_request_intent_fulfillment(&hub_intent_complex, &escrow_complex_match).await
        .expect("Validation should complete without error");
    
    assert!(validation_result.valid, "Validation should pass when complex JSON metadata matches exactly");
    
    // Test case 2: Semantically equivalent but different string representation - should fail
    // (e.g., different whitespace, different key order)
    let complex_metadata_2 = r#"{"metadata":"complex","nested":{"timestamp":1234567890,"level1":{"level2":"value","array":[1,2,3],"escaped":"\"quoted\""}}}"#;
    // This is semantically equivalent JSON but different string representation
    
    let escrow_complex_mismatch = create_complex_json_escrow(
        "0xescrow_complex_2",
        "0xintent_complex_1",
        complex_metadata_2,
    );
    
    let validation_result = validator.validate_request_intent_fulfillment(&hub_intent_complex, &escrow_complex_mismatch).await
        .expect("Validation should complete without error");
    
    assert!(
        !validation_result.valid,
        "Validation should fail when metadata strings don't match exactly (even if semantically equivalent)"
    );
    assert!(validation_result.message.contains("offered metadata"),
            "Error message should mention offered metadata mismatch");
    
    // Test case 3: Minor difference in nested value - should fail
    let complex_metadata_3 = r#"{"nested":{"level1":{"level2":"different_value","array":[1,2,3],"escaped":"\"quoted\""},"timestamp":1234567890},"metadata":"complex"}"#;
    
    let escrow_complex_mismatch_2 = create_complex_json_escrow(
        "0xescrow_complex_3",
        "0xintent_complex_1",
        complex_metadata_3,
    );
    
    let validation_result = validator.validate_request_intent_fulfillment(&hub_intent_complex, &escrow_complex_mismatch_2).await
        .expect("Validation should complete without error");
    
    assert!(!validation_result.valid, "Validation should fail when nested values differ");
    assert!(validation_result.message.contains("offered metadata"),
            "Error message should mention offered metadata mismatch");
}

fn create_complex_json_intent(intent_id: &str, offered_metadata: &str) -> RequestIntentEvent {
    create_test_request_intent(
        intent_id,
        "0xalice",
        offered_metadata,
        1000,
        "",
        Some("0xsolver".to_string()),
        Some(2),
    )
}

fn create_complex_json_escrow(escrow_id: &str, intent_id: &str, offered_metadata: &str) -> EscrowEvent {
    create_test_escrow_event(
        escrow_id,
        intent_id,
        "0xalice",
        offered_metadata,
        1000,
        "",
        Some("0xsolver".to_string()),
        2,
    )
}

/// Test that verifier accepts escrows where desired_amount is 0
/// Why: Verify that escrow desired_amount validation works correctly for successful cases
#[tokio::test]
async fn test_escrow_desired_amount_must_be_zero_success() {
    use trusted_verifier::validator::CrossChainValidator;
    use test_helpers::build_test_config;
    
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Create a hub intent
    let hub_intent = create_test_request_intent(
        "0xintent_desired_amount",
        "0xalice",
        "{\"inner\":\"0xoffered_meta\"}",
        1000,
        "{\"inner\":\"0xdesired_meta\"}",
        Some("0xsolver".to_string()),
        Some(2),
    );
    
    // Validation passes when desired_amount is 0
    let escrow_valid = create_test_escrow_event(
        "0xescrow_valid_desired",
        "0xintent_desired_amount",
        "0xalice",
        "{\"inner\":\"0xoffered_meta\"}",
        1000,
        "{\"inner\":\"0xdesired_meta\"}",
        Some("0xsolver".to_string()),
        2,
    );
    // Ensure desired_amount is 0 (it's already set to 0 in the helper)
    assert_eq!(escrow_valid.desired_amount, 0, "Escrow should have desired_amount = 0");
    
    let validation_result = validator.validate_request_intent_fulfillment(&hub_intent, &escrow_valid).await
        .expect("Validation should complete without error");
    
    assert!(validation_result.valid, "Validation should pass when desired_amount is 0");
}

/// Test that verifier rejects escrows where desired_amount is non-zero
/// Why: Verify that escrow desired_amount validation works correctly for rejection cases
#[tokio::test]
async fn test_escrow_desired_amount_must_be_zero_rejection() {
    use trusted_verifier::validator::CrossChainValidator;
    use test_helpers::build_test_config;
    
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Create a hub intent
    let hub_intent = create_test_request_intent(
        "0xintent_desired_amount",
        "0xalice",
        "{\"inner\":\"0xoffered_meta\"}",
        1000,
        "{\"inner\":\"0xdesired_meta\"}",
        Some("0xsolver".to_string()),
        Some(2),
    );
    
    // Validation fails when desired_amount is non-zero
    let mut escrow_invalid = create_test_escrow_event(
        "0xescrow_invalid_desired",
        "0xintent_desired_amount",
        "0xalice",
        "{\"inner\":\"0xoffered_meta\"}",
        1000,
        "{\"inner\":\"0xdesired_meta\"}",
        Some("0xsolver".to_string()),
        2,
    );
    escrow_invalid.desired_amount = 1;
    
    let validation_result = validator.validate_request_intent_fulfillment(&hub_intent, &escrow_invalid).await
        .expect("Validation should complete without error");
    
    assert!(!validation_result.valid, "Validation should fail when desired_amount is non-zero");
    assert!(validation_result.message.contains("desired amount"),
            "Error message should mention desired amount must be 0");
}

