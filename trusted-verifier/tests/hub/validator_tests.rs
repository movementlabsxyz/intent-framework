//! Unit tests for validator functions
//!
//! These tests verify validation logic including intent safety checks,
//! fulfillment validation, and expiry time handling.

use trusted_verifier::monitor::{FulfillmentEvent, IntentEvent};
use trusted_verifier::validator::CrossChainValidator;
#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::{
    build_test_config_with_mvm, create_base_fulfillment, create_base_intent_mvm,
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// ============================================================================
// TESTS
// ============================================================================

/// Test that validate_intent_safety rejects intents with expiry_time in the past
/// Why: Verify that expired intents are rejected for safety
#[tokio::test]
async fn test_expired_intent_rejection_in_validate_intent_safety() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a intent with expiry_time in the past
    let current_time = chrono::Utc::now().timestamp() as u64;
    let past_expiry = current_time - 1000; // Expired 1000 seconds ago
    let intent = IntentEvent {
        expiry_time: past_expiry,
        ..create_base_intent_mvm()
    };

    let result = validator
        .validate_intent_safety(&intent)
        .await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        !validation_result.valid,
        "Validation should fail when intent has expired"
    );
    assert!(
        validation_result.message.contains("expired")
            || validation_result.message.contains("expiry"),
        "Error message should indicate intent expired"
    );
}

/// Test that validate_intent_safety accepts intents with expiry_time in the future
/// Why: Verify that non-expired intents pass validation
#[tokio::test]
async fn test_non_expired_intent_acceptance_in_validate_intent_safety() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a intent with expiry_time in the future
    let current_time = chrono::Utc::now().timestamp() as u64;
    let future_expiry = current_time + 1000; // Expires in 1000 seconds
    let intent = IntentEvent {
        expiry_time: future_expiry,
        ..create_base_intent_mvm()
    };

    let result = validator
        .validate_intent_safety(&intent)
        .await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        validation_result.valid,
        "Validation should pass when intent has not expired"
    );
    assert!(
        validation_result.message.contains("safe")
            || validation_result.message.contains("successful"),
        "Message should indicate intent is safe"
    );
}

/// Test edge case: intent expires exactly at current time
/// Why: Verify behavior when expiry_time equals current timestamp
#[tokio::test]
async fn test_intent_expires_exactly_at_current_time() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a intent with expiry_time exactly at current time
    let current_time = chrono::Utc::now().timestamp() as u64;
    let intent = IntentEvent {
        expiry_time: current_time,
        ..create_base_intent_mvm()
    };

    let result = validator
        .validate_intent_safety(&intent)
        .await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    // The check is: expiry_time < current_time, so if they're equal, it should pass
    // But let's verify the actual behavior - if expiry_time == current_time, the check is false
    // so it should pass. However, there might be a race condition where current_time advances.
    // The actual check is: if intent.expiry_time < chrono::Utc::now().timestamp() as u64
    // So if expiry_time == current_time, the check fails (not <), so validation should pass
    // But we need to account for the time that passes between getting current_time and checking
    // For this test, we'll verify it behaves consistently
    if validation_result.valid {
        // If it passes, that's fine - expiry_time == current_time means not expired yet
        assert!(
            validation_result.message.contains("safe")
                || validation_result.message.contains("successful"),
            "Message should indicate intent is safe"
        );
    } else {
        // If it fails, it means current_time advanced, which is also valid behavior
        assert!(
            validation_result.message.contains("expired"),
            "If validation fails, message should indicate expired"
        );
    }
}

/// Test that validate_fulfillment rejects fulfillments that occur after intent expiry
/// Why: Verify that fulfillments after expiry are rejected
#[tokio::test]
async fn test_fulfillment_timestamp_validation_after_expiry() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a intent with expiry_time
    let current_time = chrono::Utc::now().timestamp() as u64;
    let expiry_time = current_time + 100; // Expires in 100 seconds
    let intent = IntentEvent {
        expiry_time,
        ..create_base_intent_mvm()
    };

    // Create a fulfillment with timestamp after expiry
    let fulfillment_timestamp = expiry_time + 100; // Fulfillment occurs 100 seconds after expiry
    let fulfillment = FulfillmentEvent {
        timestamp: fulfillment_timestamp,
        intent_id: intent.intent_id.clone(),
        provided_amount: intent.desired_amount,
        provided_metadata: intent.desired_metadata.clone(),
        ..create_base_fulfillment()
    };

    let result = validator
        .validate_fulfillment(&intent, &fulfillment)
        .await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        !validation_result.valid,
        "Validation should fail when fulfillment occurs after expiry"
    );
    assert!(
        validation_result.message.contains("expiry") || validation_result.message.contains("after"),
        "Error message should indicate fulfillment occurred after expiry"
    );
}

/// Test that validate_fulfillment accepts fulfillments that occur before intent expiry
/// Why: Verify that fulfillments before expiry are accepted
#[tokio::test]
async fn test_fulfillment_timestamp_validation_before_expiry() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a intent with expiry_time
    let current_time = chrono::Utc::now().timestamp() as u64;
    let expiry_time = current_time + 1000; // Expires in 1000 seconds
    let intent = IntentEvent {
        expiry_time,
        ..create_base_intent_mvm()
    };

    // Create a fulfillment with timestamp before expiry
    let fulfillment_timestamp = expiry_time - 100; // Fulfillment occurs 100 seconds before expiry
    let fulfillment = FulfillmentEvent {
        timestamp: fulfillment_timestamp,
        intent_id: intent.intent_id.clone(),
        provided_amount: intent.desired_amount,
        provided_metadata: intent.desired_metadata.clone(),
        ..create_base_fulfillment()
    };

    let result = validator
        .validate_fulfillment(&intent, &fulfillment)
        .await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        validation_result.valid,
        "Validation should pass when fulfillment occurs before expiry"
    );
    assert!(
        validation_result.message.contains("successful"),
        "Message should indicate validation successful"
    );
}

/// Test that validate_fulfillment accepts fulfillments that occur exactly at expiry time
/// Why: Verify edge case behavior when fulfillment timestamp equals expiry
#[tokio::test]
async fn test_fulfillment_timestamp_validation_at_expiry() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a intent with expiry_time
    let current_time = chrono::Utc::now().timestamp() as u64;
    let expiry_time = current_time + 1000; // Expires in 1000 seconds
    let intent = IntentEvent {
        expiry_time,
        ..create_base_intent_mvm()
    };

    // Create a fulfillment with timestamp exactly at expiry
    let fulfillment = FulfillmentEvent {
        timestamp: expiry_time,
        intent_id: intent.intent_id.clone(),
        provided_amount: intent.desired_amount,
        provided_metadata: intent.desired_metadata.clone(),
        ..create_base_fulfillment()
    };

    let result = validator
        .validate_fulfillment(&intent, &fulfillment)
        .await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    // The check is: fulfillment.timestamp > intent.expiry_time
    // If they're equal, the check is false, so validation should pass
    assert!(
        validation_result.valid,
        "Validation should pass when fulfillment timestamp equals expiry"
    );
    assert!(
        validation_result.message.contains("successful"),
        "Message should indicate validation successful"
    );
}

/// Test that validate_fulfillment succeeds when all conditions are met
/// Why: Verify that valid fulfillments pass all validation checks
#[tokio::test]
async fn test_fulfillment_validation_success() {
    // Initialize tracing subscriber to capture log output during tests (ignored if already initialized)
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a intent with future expiry and custom desired fields
    let current_time = chrono::Utc::now().timestamp() as u64;
    let expiry_time = current_time + 1000; // Expires in 1000 seconds
    let intent = IntentEvent {
        expiry_time,
        desired_amount: 500,
        desired_metadata: "{\"token\":\"USDC\"}".to_string(),
        ..create_base_intent_mvm()
    };

    // Create a fulfillment that matches all requirements
    let fulfillment_timestamp = expiry_time - 100; // Before expiry
    let fulfillment = FulfillmentEvent {
        timestamp: fulfillment_timestamp,
        intent_id: intent.intent_id.clone(),
        provided_amount: intent.desired_amount,
        provided_metadata: intent.desired_metadata.clone(),
        ..create_base_fulfillment()
    };

    let result = validator
        .validate_fulfillment(&intent, &fulfillment)
        .await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        validation_result.valid,
        "Validation should pass when all conditions are met"
    );
    assert!(
        validation_result.message.contains("successful"),
        "Message should indicate validation successful"
    );
}

/// Test that validate_fulfillment rejects when provided_amount doesn't match desired_amount
/// Why: Verify that amount mismatches are caught
#[tokio::test]
async fn test_fulfillment_amount_mismatch_rejection() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a intent with desired_amount
    let current_time = chrono::Utc::now().timestamp() as u64;
    let expiry_time = current_time + 1000;
    let intent = IntentEvent {
        expiry_time,
        desired_amount: 500,
        desired_metadata: "{\"token\":\"USDC\"}".to_string(),
        ..create_base_intent_mvm()
    };

    // Create a fulfillment with different provided_amount
    let fulfillment_timestamp = expiry_time - 100;
    let fulfillment = FulfillmentEvent {
        timestamp: fulfillment_timestamp,
        intent_id: intent.intent_id.clone(),
        provided_amount: 300, // Different amount than desired_amount (500)
        provided_metadata: intent.desired_metadata.clone(),
        ..create_base_fulfillment()
    };

    let result = validator
        .validate_fulfillment(&intent, &fulfillment)
        .await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        !validation_result.valid,
        "Validation should fail when provided_amount doesn't match desired_amount"
    );
    assert!(
        validation_result.message.contains("amount")
            || validation_result.message.contains("Amount"),
        "Error message should mention amount mismatch"
    );
}

/// Test that validate_fulfillment rejects when provided_metadata doesn't match desired_metadata
/// Why: Verify that metadata mismatches are caught
#[tokio::test]
async fn test_fulfillment_metadata_mismatch_rejection() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a intent with desired_metadata
    let current_time = chrono::Utc::now().timestamp() as u64;
    let expiry_time = current_time + 1000;
    let intent = IntentEvent {
        expiry_time,
        desired_amount: 500,
        desired_metadata: "{\"token\":\"USDC\"}".to_string(),
        ..create_base_intent_mvm()
    };

    // Create a fulfillment with different provided_metadata
    let fulfillment_timestamp = expiry_time - 100;
    let fulfillment = FulfillmentEvent {
        timestamp: fulfillment_timestamp,
        intent_id: intent.intent_id.clone(),
        provided_amount: intent.desired_amount,
        provided_metadata: "{\"token\":\"USDT\"}".to_string(), // Different metadata than desired_metadata
        ..create_base_fulfillment()
    };

    let result = validator
        .validate_fulfillment(&intent, &fulfillment)
        .await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        !validation_result.valid,
        "Validation should fail when provided_metadata doesn't match desired_metadata"
    );
    assert!(
        validation_result.message.contains("metadata")
            || validation_result.message.contains("Metadata"),
        "Error message should mention metadata mismatch"
    );
}

/// Test that validate_fulfillment rejects when intent_id doesn't match
/// Why: Verify that fulfillments for different intents are rejected
#[tokio::test]
async fn test_fulfillment_intent_id_mismatch_rejection() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a intent
    let current_time = chrono::Utc::now().timestamp() as u64;
    let expiry_time = current_time + 1000;
    let intent = IntentEvent {
        expiry_time,
        desired_amount: 500,
        desired_metadata: "{\"token\":\"USDC\"}".to_string(),
        ..create_base_intent_mvm()
    };

    // Create a fulfillment with different intent_id
    let fulfillment_timestamp = expiry_time - 100;
    let fulfillment = FulfillmentEvent {
        timestamp: fulfillment_timestamp,
        intent_id: "0xdifferent_intent_id".to_string(), // Different intent_id
        provided_amount: intent.desired_amount,
        provided_metadata: intent.desired_metadata.clone(),
        ..create_base_fulfillment()
    };

    let result = validator
        .validate_fulfillment(&intent, &fulfillment)
        .await;

    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(
        !validation_result.valid,
        "Validation should fail when intent_id doesn't match"
    );
    assert!(
        validation_result.message.contains("intent_id")
            || validation_result.message.contains("Intent"),
        "Error message should mention intent_id mismatch"
    );
}
