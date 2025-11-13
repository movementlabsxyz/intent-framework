//! Unit tests for validator functions
//!
//! These tests verify validation logic including request intent safety checks,
//! fulfillment validation, and expiry time handling.

use trusted_verifier::validator::CrossChainValidator;
use trusted_verifier::monitor::{RequestIntentEvent, FulfillmentEvent};
#[path = "mod.rs"]
mod test_helpers;
use test_helpers::build_test_config;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a test request intent with the given expiry time
fn create_test_request_intent_with_expiry(expiry_time: u64) -> RequestIntentEvent {
    RequestIntentEvent {
        chain: "hub".to_string(),
        intent_id: "0xintent123".to_string(),
        issuer: "0xalice".to_string(),
        offered_metadata: "{}".to_string(),
        offered_amount: 1000,
        desired_metadata: "{}".to_string(),
        desired_amount: 0,
        expiry_time,
        revocable: false,
        solver: None,
        connected_chain_id: Some(2),
        timestamp: 0,
    }
}

/// Create a test fulfillment event with the given timestamp and request intent details
fn create_test_fulfillment(timestamp: u64, intent_id: &str, provided_amount: u64, provided_metadata: &str) -> FulfillmentEvent {
    FulfillmentEvent {
        chain: "hub".to_string(),
        intent_id: intent_id.to_string(),
        intent_address: "0xaddr".to_string(),
        solver: "0xsolver".to_string(),
        provided_metadata: provided_metadata.to_string(),
        provided_amount,
        timestamp,
    }
}

// ============================================================================
// TESTS
// ============================================================================

/// Test that validate_request_intent_safety rejects request intents with expiry_time in the past
/// Why: Verify that expired request intents are rejected for safety
#[tokio::test]
async fn test_expired_request_intent_rejection_in_validate_request_intent_safety() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Create a request intent with expiry_time in the past
    let current_time = chrono::Utc::now().timestamp() as u64;
    let past_expiry = current_time - 1000; // Expired 1000 seconds ago
    let request_intent = create_test_request_intent_with_expiry(past_expiry);
    
    let result = validator.validate_request_intent_safety(&request_intent).await;
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(!validation_result.valid, "Validation should fail when request intent has expired");
    assert!(validation_result.message.contains("expired") ||
            validation_result.message.contains("expiry"),
            "Error message should indicate request intent expired");
}

/// Test that validate_request_intent_safety accepts request intents with expiry_time in the future
/// Why: Verify that non-expired request intents pass validation
#[tokio::test]
async fn test_non_expired_request_intent_acceptance_in_validate_request_intent_safety() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Create a request intent with expiry_time in the future
    let current_time = chrono::Utc::now().timestamp() as u64;
    let future_expiry = current_time + 1000; // Expires in 1000 seconds
    let request_intent = create_test_request_intent_with_expiry(future_expiry);
    
    let result = validator.validate_request_intent_safety(&request_intent).await;
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(validation_result.valid, "Validation should pass when request intent has not expired");
    assert!(validation_result.message.contains("safe") ||
            validation_result.message.contains("successful"),
            "Message should indicate request intent is safe");
}

/// Test edge case: request intent expires exactly at current time
/// Why: Verify behavior when expiry_time equals current timestamp
#[tokio::test]
async fn test_request_intent_expires_exactly_at_current_time() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Create a request intent with expiry_time exactly at current time
    let current_time = chrono::Utc::now().timestamp() as u64;
    let request_intent = create_test_request_intent_with_expiry(current_time);
    
    let result = validator.validate_request_intent_safety(&request_intent).await;
    
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
        assert!(validation_result.message.contains("safe") ||
                validation_result.message.contains("successful"),
                "Message should indicate intent is safe");
    } else {
        // If it fails, it means current_time advanced, which is also valid behavior
        assert!(validation_result.message.contains("expired"),
                "If validation fails, message should indicate expired");
    }
}

/// Test that validate_fulfillment rejects fulfillments that occur after request intent expiry
/// Why: Verify that fulfillments after expiry are rejected
#[tokio::test]
async fn test_fulfillment_timestamp_validation_after_expiry() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Create a request intent with expiry_time
    let current_time = chrono::Utc::now().timestamp() as u64;
    let expiry_time = current_time + 100; // Expires in 100 seconds
    let request_intent = create_test_request_intent_with_expiry(expiry_time);
    
    // Create a fulfillment with timestamp after expiry
    let fulfillment_timestamp = expiry_time + 100; // Fulfillment occurs 100 seconds after expiry
    let fulfillment = create_test_fulfillment(
        fulfillment_timestamp,
        &request_intent.intent_id,
        request_intent.desired_amount,
        &request_intent.desired_metadata,
    );
    
    let result = validator.validate_fulfillment(&request_intent, &fulfillment).await;
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(!validation_result.valid, "Validation should fail when fulfillment occurs after expiry");
    assert!(validation_result.message.contains("expiry") ||
            validation_result.message.contains("after"),
            "Error message should indicate fulfillment occurred after expiry");
}

/// Test that validate_fulfillment accepts fulfillments that occur before request intent expiry
/// Why: Verify that fulfillments before expiry are accepted
#[tokio::test]
async fn test_fulfillment_timestamp_validation_before_expiry() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Create a request intent with expiry_time
    let current_time = chrono::Utc::now().timestamp() as u64;
    let expiry_time = current_time + 1000; // Expires in 1000 seconds
    let request_intent = create_test_request_intent_with_expiry(expiry_time);
    
    // Create a fulfillment with timestamp before expiry
    let fulfillment_timestamp = expiry_time - 100; // Fulfillment occurs 100 seconds before expiry
    let fulfillment = create_test_fulfillment(
        fulfillment_timestamp,
        &request_intent.intent_id,
        request_intent.desired_amount,
        &request_intent.desired_metadata,
    );
    
    let result = validator.validate_fulfillment(&request_intent, &fulfillment).await;
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    assert!(validation_result.valid, "Validation should pass when fulfillment occurs before expiry");
    assert!(validation_result.message.contains("successful"),
            "Message should indicate validation successful");
}

/// Test that validate_fulfillment accepts fulfillments that occur exactly at expiry time
/// Why: Verify edge case behavior when fulfillment timestamp equals expiry
#[tokio::test]
async fn test_fulfillment_timestamp_validation_at_expiry() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Create a request intent with expiry_time
    let current_time = chrono::Utc::now().timestamp() as u64;
    let expiry_time = current_time + 1000; // Expires in 1000 seconds
    let request_intent = create_test_request_intent_with_expiry(expiry_time);
    
    // Create a fulfillment with timestamp exactly at expiry
    let fulfillment = create_test_fulfillment(
        expiry_time,
        &request_intent.intent_id,
        request_intent.desired_amount,
        &request_intent.desired_metadata,
    );
    
    let result = validator.validate_fulfillment(&request_intent, &fulfillment).await;
    
    assert!(result.is_ok(), "Validation should complete without error");
    let validation_result = result.unwrap();
    // The check is: fulfillment.timestamp > request_intent.expiry_time
    // If they're equal, the check is false, so validation should pass
    assert!(validation_result.valid, "Validation should pass when fulfillment timestamp equals expiry");
    assert!(validation_result.message.contains("successful"),
            "Message should indicate validation successful");
}

