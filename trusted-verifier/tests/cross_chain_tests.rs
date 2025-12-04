//! Unit tests for cross-chain matching logic
//!
//! These tests verify that escrow events can be matched to intent events
//! across different chains using intent_id.

use trusted_verifier::monitor::{EscrowEvent, IntentEvent};
#[path = "mod.rs"]
mod test_helpers;
use test_helpers::{create_base_escrow_event, create_base_intent_mvm};

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
    let hub_intent = create_base_intent_mvm();

    // Step 2: User creates escrow on connected chain WITH tokens locked in it
    // The user must manually provide the hub_intent_id when creating the escrow
    let escrow_creation = create_base_escrow_event();

    // Step 3: Solver fulfills hub intent (solver provides 1000 tokens on hub chain)
    // [Not yet tested. This will also be tested here, not just in integration tests.]

    // Step 4: Verifier validation
    // [Not yet tested. This will also be tested here, not just in integration tests.]

    // Step 5: Verifier release
    // [Not yet tested. This will also be tested here, not just in integration tests.]

    // This unit test verifies that data structures support cross-chain matching
    // Verify matching: intent_id should match
    assert_eq!(
        escrow_creation.intent_id, hub_intent.intent_id,
        "Escrow intent_id should match the hub intent_id"
    );

    // Verify escrow has tokens locked (user creates escrow with tokens locked)
    assert_eq!(
        escrow_creation.offered_amount, 1000,
        "Escrow should have tokens locked (user created escrow with tokens)"
    );

    // Verify the locked tokens in escrow match what the intent wants
    assert_eq!(
        escrow_creation.offered_amount, hub_intent.offered_amount,
        "Escrow locked tokens should match what intent wants"
    );
}

/// Test that escrow chain_id validation works correctly
/// Why: Verify that escrow chain_id matches the intent's offered_chain_id when provided
#[tokio::test]
async fn test_escrow_chain_id_validation() {
    use test_helpers::build_test_config_with_mvm;
    use trusted_verifier::validator::CrossChainValidator;

    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Test that escrow chain_id must match intent's offered_chain_id when provided
    let valid_intent = create_base_intent_mvm();
    let valid_escrow = create_base_escrow_event();

    // This should pass the connected_chain_id check (may fail other validations, but not this one)
    let result = trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
        &validator,
        &valid_intent,
        &valid_escrow,
    )
    .await;
    assert!(result.is_ok(), "Validation should complete");

    let validation_result = result.unwrap();
    // Assert 1: If validation fails, it should NOT be because of missing connected_chain_id
    if !validation_result.valid {
        assert!(
            !validation_result.message.contains("connected_chain_id"),
            "Should not fail due to missing connected_chain_id when chain_id is provided"
        );
    }
    // Assert 2: Validation may fail on other checks (like solver registry query), but should not fail on connected_chain_id
    // Note: This might fail other validations (like solver address mismatch if not properly mocked),
    // but for a complete test, we'd need to ensure all conditions are met
    // We just verify it doesn't fail on connected_chain_id check
}

/// Test that verifier rejects escrows where offered_amount doesn't match hub intent's offered amount
/// Why: Verify that escrow amount validation works correctly
#[tokio::test]
async fn test_escrow_amount_must_match_hub_intent_offered_amount() {
    use test_helpers::build_test_config_with_mvm;
    use trusted_verifier::validator::CrossChainValidator;

    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a hub intent with offered_amount = 1000
    let hub_intent = create_base_intent_mvm();

    // Create an escrow with mismatched offered_amount (500 != 1000)
    let escrow_mismatch = EscrowEvent {
        offered_amount: 500,
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent,
            &escrow_mismatch,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        !validation_result.valid,
        "Validation should fail when escrow offered_amount doesn't match hub intent offered amount"
    );
    assert!(
        validation_result.message.contains("offered amount"),
        "Error message should mention offered amount mismatch"
    );

    // Now test with matching amounts
    let escrow_match = create_base_escrow_event();

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent,
            &escrow_match,
        )
        .await
        .expect("Validation should complete without error");

    // Verify that validation doesn't fail due to amount mismatch (amount check passes)
    assert!(
        !validation_result.message.contains("offered amount"),
        "Validation should not fail due to offered_amount mismatch when amounts match"
    );

    // Verify that validation doesn't fail at all (all checks pass)
    assert!(
        validation_result.valid,
        "Validation should pass when all checks pass"
    );
}

/// Test that verifier accepts escrows where offered_metadata exactly matches hub intent's offered_metadata
/// Why: Verify that metadata matching validation works correctly for successful cases
#[tokio::test]
async fn test_escrow_offered_metadata_must_match_hub_intent_offered_metadata_success() {
    use test_helpers::build_test_config_with_mvm;
    use trusted_verifier::validator::CrossChainValidator;

    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a hub intent with specific offered_metadata
    let hub_intent = create_base_intent_mvm();

    // Create an escrow with matching offered_metadata
    let escrow_match = create_base_escrow_event();

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent,
            &escrow_match,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        validation_result.valid,
        "Validation should pass when offered_metadata matches"
    );
    assert!(
        !validation_result.message.contains("offered metadata"),
        "Error message should not mention offered metadata mismatch when metadata matches"
    );
}

/// Test that verifier rejects escrows where offered_metadata doesn't match hub intent's offered_metadata
/// Why: Verify that metadata mismatch validation works correctly
#[tokio::test]
async fn test_escrow_offered_metadata_must_match_hub_intent_offered_metadata_rejection() {
    use test_helpers::build_test_config_with_mvm;
    use trusted_verifier::validator::CrossChainValidator;

    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a hub intent with specific offered_metadata
    let hub_intent = create_base_intent_mvm();

    // Create an escrow with mismatched offered_metadata
    let escrow_mismatch = EscrowEvent {
        offered_metadata: "{\"inner\":\"0xdifferent_meta\"}".to_string(),
        ..create_base_escrow_event()
    };

    // The validation function should complete successfully (return Ok, not Err)
    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent,
            &escrow_mismatch,
        )
        .await
        .expect("Validation should complete without error");

    // But the validation result should indicate failure (valid = false) because metadata doesn't match
    assert!(
        !validation_result.valid,
        "Validation should fail when offered_metadata doesn't match"
    );
    assert!(
        validation_result.message.contains("offered metadata"),
        "Error message should mention offered metadata mismatch"
    );
}

/// Test that verifier correctly handles empty metadata strings
/// Why: Verify that empty metadata strings are handled correctly (both empty should match, one empty one not should fail)
#[tokio::test]
async fn test_escrow_offered_metadata_empty_strings() {
    use test_helpers::build_test_config_with_mvm;
    use trusted_verifier::validator::CrossChainValidator;

    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Test case 1: Both empty - should pass
    let hub_intent_empty = IntentEvent {
        offered_metadata: "".to_string(),
        ..create_base_intent_mvm()
    };
    let escrow_empty = EscrowEvent {
        offered_metadata: "".to_string(),
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent_empty,
            &escrow_empty,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        validation_result.valid,
        "Validation should pass when both metadata strings are empty"
    );

    // Test case 2: Hub intent has metadata, escrow is empty - should fail
    let hub_intent_with_meta = IntentEvent {
        offered_metadata: "{\"inner\":\"0xoffered_meta\"}".to_string(),
        ..create_base_intent_mvm()
    };
    let escrow_empty_2 = EscrowEvent {
        offered_metadata: "".to_string(),
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent_with_meta,
            &escrow_empty_2,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        !validation_result.valid,
        "Validation should fail when hub intent has metadata but escrow is empty"
    );
    assert!(
        validation_result.message.contains("offered metadata"),
        "Error message should mention offered metadata mismatch"
    );

    // Test case 3: Hub intent is empty, escrow has metadata - should fail
    let hub_intent_empty_3 = IntentEvent {
        offered_metadata: "".to_string(),
        ..create_base_intent_mvm()
    };
    let escrow_with_meta = EscrowEvent {
        offered_metadata: "{\"inner\":\"0xoffered_meta\"}".to_string(),
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent_empty_3,
            &escrow_with_meta,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        !validation_result.valid,
        "Validation should fail when hub intent is empty but escrow has metadata"
    );
    assert!(
        validation_result.message.contains("offered metadata"),
        "Error message should mention offered metadata mismatch"
    );
}

/// Test that verifier correctly handles complex JSON metadata structures
/// Why: Verify that exact string matching works for complex nested JSON, escaped characters, etc.
#[tokio::test]
async fn test_escrow_offered_metadata_complex_json() {
    use test_helpers::build_test_config_with_mvm;
    use trusted_verifier::validator::CrossChainValidator;

    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Test case 1: Complex nested JSON - should pass when exact match
    let complex_metadata = r#"{"nested":{"level1":{"level2":"value","array":[1,2,3],"escaped":"\"quoted\""},"timestamp":1234567890},"metadata":"complex"}"#;

    let hub_intent_complex = IntentEvent {
        offered_metadata: complex_metadata.to_string(),
        ..create_base_intent_mvm()
    };
    let escrow_complex_match = EscrowEvent {
        offered_metadata: complex_metadata.to_string(),
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent_complex,
            &escrow_complex_match,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        validation_result.valid,
        "Validation should pass when complex JSON metadata matches exactly"
    );

    // Test case 2: Semantically equivalent but different string representation - should fail
    // (e.g., different whitespace, different key order)
    let complex_metadata_2 = r#"{"metadata":"complex","nested":{"timestamp":1234567890,"level1":{"level2":"value","array":[1,2,3],"escaped":"\"quoted\""}}}"#;
    // This is semantically equivalent JSON but different string representation

    let escrow_complex_mismatch = EscrowEvent {
        offered_metadata: complex_metadata_2.to_string(),
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent_complex,
            &escrow_complex_mismatch,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        !validation_result.valid,
        "Validation should fail when metadata strings don't match exactly (even if semantically equivalent)"
    );
    assert!(
        validation_result.message.contains("offered metadata"),
        "Error message should mention offered metadata mismatch"
    );

    // Test case 3: Minor difference in nested value - should fail
    let complex_metadata_3 = r#"{"nested":{"level1":{"level2":"different_value","array":[1,2,3],"escaped":"\"quoted\""},"timestamp":1234567890},"metadata":"complex"}"#;

    let escrow_complex_mismatch_2 = EscrowEvent {
        offered_metadata: complex_metadata_3.to_string(),
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent_complex,
            &escrow_complex_mismatch_2,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        !validation_result.valid,
        "Validation should fail when nested values differ"
    );
    assert!(
        validation_result.message.contains("offered metadata"),
        "Error message should mention offered metadata mismatch"
    );
}

/// Test that verifier accepts escrows where desired_amount is 0
/// Why: Verify that escrow desired_amount validation works correctly for successful cases
#[tokio::test]
async fn test_escrow_desired_amount_must_be_zero_success() {
    use test_helpers::build_test_config_with_mvm;
    use trusted_verifier::validator::CrossChainValidator;

    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a hub intent
    let hub_intent = create_base_intent_mvm();

    // Validation passes when desired_amount is 0
    let escrow_valid = create_base_escrow_event();
    // Ensure desired_amount is 0 (it's already set to 0 in the helper)
    assert_eq!(
        escrow_valid.desired_amount, 0,
        "Escrow should have desired_amount = 0"
    );

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent,
            &escrow_valid,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        validation_result.valid,
        "Validation should pass when desired_amount is 0"
    );
}

/// Test that verifier rejects escrows where desired_amount is non-zero
/// Why: Verify that escrow desired_amount validation works correctly for rejection cases
#[tokio::test]
async fn test_escrow_desired_amount_must_be_zero_rejection() {
    use test_helpers::build_test_config_with_mvm;
    use trusted_verifier::validator::CrossChainValidator;

    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a hub intent
    let hub_intent = create_base_intent_mvm();

    // Validation fails when desired_amount is non-zero
    let escrow_invalid = EscrowEvent {
        desired_amount: 1,
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent,
            &escrow_invalid,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        !validation_result.valid,
        "Validation should fail when desired_amount is non-zero"
    );
    assert!(
        validation_result.message.contains("desired amount"),
        "Error message should mention desired amount must be 0"
    );
}

/// Test that verifier rejects escrows when intent has no connected_chain_id
/// Why: Verify that intents must specify connected_chain_id for escrow validation
#[tokio::test]
async fn test_escrow_rejection_when_connected_chain_id_is_none() {
    use test_helpers::build_test_config_with_mvm;
    use trusted_verifier::validator::CrossChainValidator;

    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a hub intent without connected_chain_id
    let hub_intent = IntentEvent {
        connected_chain_id: None,
        ..create_base_intent_mvm()
    };

    // Create an escrow with a chain_id
    let escrow = EscrowEvent {
        chain_id: 999,
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent,
            &escrow,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        !validation_result.valid,
        "Validation should fail when intent has no connected_chain_id"
    );
    assert!(
        validation_result
            .message
            .contains("must specify connected_chain_id"),
        "Error message should mention that connected_chain_id must be specified"
    );
}

/// Test that verifier rejects escrows when connected_chain_id doesn't match escrow chain_id
/// Why: Verify that chain_id mismatch validation works correctly
#[tokio::test]
async fn test_escrow_chain_id_mismatch_rejection() {
    use test_helpers::build_test_config_with_mvm;
    use trusted_verifier::validator::CrossChainValidator;

    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a hub intent with connected_chain_id
    let hub_intent = IntentEvent {
        connected_chain_id: Some(31337),
        ..create_base_intent_mvm()
    };

    // Create an escrow with mismatched chain_id
    let escrow_mismatch = EscrowEvent {
        chain_id: 999, // Different from connected_chain_id (31337)
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent,
            &escrow_mismatch,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        !validation_result.valid,
        "Validation should fail when chain_id doesn't match connected_chain_id"
    );
    assert!(
        validation_result.message.contains("does not match"),
        "Error message should mention chain_id does not match"
    );
}
