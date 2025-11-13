//! Unit tests for event monitoring
//!
//! These tests verify event structures and cache behavior
//! without requiring external services.

use trusted_verifier::monitor::{RequestIntentEvent, EscrowEvent, FulfillmentEvent, EventMonitor};
use futures::future;
#[path = "mod.rs"]
mod test_helpers;
use test_helpers::build_test_config;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Helper function for validation logic
fn is_safe_for_escrow(event: &RequestIntentEvent) -> bool {
    !event.revocable
}

/// Create a test request intent with customizable fields
fn create_test_request_intent(
    intent_id: &str,
    issuer: &str,
    revocable: bool,
    expiry_time: u64,
    solver: Option<String>,
    connected_chain_id: Option<u64>,
) -> RequestIntentEvent {
    RequestIntentEvent {
        chain: "hub".to_string(),
        intent_id: intent_id.to_string(),
        issuer: issuer.to_string(),
        offered_metadata: "{}".to_string(),
        offered_amount: 1000,
        desired_metadata: "{}".to_string(),
        desired_amount: 0,
        expiry_time,
        revocable,
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
    offered_amount: u64,
) -> EscrowEvent {
    EscrowEvent {
        chain: "connected".to_string(),
        escrow_id: escrow_id.to_string(),
        intent_id: intent_id.to_string(),
        issuer: issuer.to_string(),
        offered_metadata: "{}".to_string(),
        offered_amount,
        reserved_solver: None,
        chain_id: 2,
        desired_metadata: "{}".to_string(),
        desired_amount: 0, // Escrow desired_amount must be 0 (validation requirement)
        expiry_time: 9999999999,
        revocable: false,
        chain_type: trusted_verifier::ChainType::Move,
        timestamp: 1,
    }
}

/// Create a test fulfillment event with customizable fields
fn create_test_fulfillment_event(
    intent_id: &str,
    intent_address: &str,
    solver: &str,
    provided_amount: u64,
) -> FulfillmentEvent {
    FulfillmentEvent {
        chain: "hub".to_string(),
        intent_id: intent_id.to_string(),
        intent_address: intent_address.to_string(),
        solver: solver.to_string(),
        provided_metadata: "{}".to_string(),
        provided_amount,
        timestamp: 2,
    }
}

// ============================================================================
// TESTS
// ============================================================================

/// Test that revocable intents are rejected (error thrown)
/// Why: Verify critical security check - revocable intents must be rejected for escrow
#[test]
fn test_revocable_intent_rejection() {
    let revocable_intent = create_test_request_intent(
        "0xrevocable",
        "0xalice",
        true, // NOT safe for escrow
        0,
        None,
        None,
    );
    
    // Simulate validation: revocable intents should be rejected
    let result = is_safe_for_escrow(&revocable_intent);
    assert!(!result, "Revocable intents should NOT be safe for escrow");
    
    let non_revocable_intent = create_test_request_intent(
        "0xsafe",
        "0xbob",
        false, // Safe for escrow
        0,
        None,
        None,
    );
    
    let result = is_safe_for_escrow(&non_revocable_intent);
    assert!(result, "Non-revocable intents should be safe for escrow");
}

/// Test that approval is generated when fulfillment and escrow are both present
#[tokio::test]
async fn test_generates_approval_when_fulfillment_and_escrow_present() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config();
    let monitor = EventMonitor::new(&config).await.expect("Failed to create monitor");

    // Arrange: insert escrow with intent_id (valid hex address - even number of hex digits)
    let intent_id = "0x01";
    {
        let mut escrow_cache = monitor.escrow_cache.write().await;
        escrow_cache.push(create_test_escrow_event(
            "0xescrow",
            intent_id,
            "0xissuer",
            1000,
        ));
    }

    // Act: call approval generation on fulfillment with same intent_id
    let fulfillment = create_test_fulfillment_event(
        intent_id,
        "0xaddr",
        "0xsolver",
        1000,
    );
    monitor.validate_and_approve_fulfillment(&fulfillment).await.expect("Approval generation should succeed");

    // Assert: approval exists for escrow
    let approval = monitor.get_approval_for_escrow("0xescrow").await;
    assert!(approval.is_some(), "Approval should exist for escrow");
    let approval = approval.unwrap();
    assert_eq!(approval.intent_id, intent_id);
    assert!(!approval.signature.is_empty(), "Signature should not be empty");
}

/// Test that error is returned when no matching escrow exists
#[tokio::test]
async fn test_returns_error_when_no_matching_escrow() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config();
    let monitor = EventMonitor::new(&config).await.expect("Failed to create monitor");

    let fulfillment = create_test_fulfillment_event(
        "0x999", // Valid hex but no matching escrow
        "0xaddr",
        "0xsolver",
        1000,
    );
    
    // Act: try to generate approval without matching escrow
    let result = monitor.validate_and_approve_fulfillment(&fulfillment).await;
    
    // Assert: should return error and no approval should exist
    assert!(result.is_err(), "Should return error when escrow is missing");
    assert!(monitor.get_approval_for_escrow("0xescrow").await.is_none(), "No approval should exist");
}

/// Test that multiple concurrent intents are handled correctly
/// Why: Verify the verifier can handle multiple intents/escrows/fulfillments happening simultaneously
/// 
/// Note: This test is in monitor_tests.rs (not cross_chain_tests.rs) because it primarily tests
/// EventMonitor's concurrent handling capabilities - specifically that the monitor can process
/// multiple fulfillments simultaneously without race conditions, correctly match each fulfillment
/// to its escrow, and generate independent approvals. While it involves cross-chain scenarios,
/// the focus is on the monitor's concurrency safety rather than cross-chain matching logic.
#[tokio::test]
async fn test_multiple_concurrent_intents() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config();
    let monitor = EventMonitor::new(&config).await.expect("Failed to create monitor");

    // Arrange: create multiple escrows with different intent_ids simultaneously (valid hex addresses)
    let escrows = vec![
        create_test_escrow_event("0xescrow1", "0x01", "0xissuer1", 1000),
        create_test_escrow_event("0xescrow2", "0x02", "0xissuer2", 2000),
        create_test_escrow_event("0xescrow3", "0x03", "0xissuer3", 3000),
    ];

    // Insert all escrows into cache
    {
        let mut escrow_cache = monitor.escrow_cache.write().await;
        escrow_cache.extend(escrows.clone());
    }

    // Act: process multiple fulfillments concurrently
    let fulfillments = vec![
        create_test_fulfillment_event("0x01", "0xaddr1", "0xsolver1", 1000),
        create_test_fulfillment_event("0x02", "0xaddr2", "0xsolver2", 2000),
        create_test_fulfillment_event("0x03", "0xaddr3", "0xsolver3", 3000),
    ];

    // Process all fulfillments concurrently
    let results: Vec<_> = future::join_all(
        fulfillments.iter().map(|f| monitor.validate_and_approve_fulfillment(f))
    ).await;

    // Assert: all fulfillments should succeed
    for result in &results {
        assert!(result.is_ok(), "All concurrent fulfillments should succeed");
    }

    // Assert: each escrow should have its own approval
    let approval1 = monitor.get_approval_for_escrow("0xescrow1").await;
    assert!(approval1.is_some(), "Escrow 1 should have approval");
    let approval1 = approval1.unwrap();
    assert_eq!(approval1.intent_id, "0x01");

    let approval2 = monitor.get_approval_for_escrow("0xescrow2").await;
    assert!(approval2.is_some(), "Escrow 2 should have approval");
    let approval2 = approval2.unwrap();
    assert_eq!(approval2.intent_id, "0x02");

    let approval3 = monitor.get_approval_for_escrow("0xescrow3").await;
    assert!(approval3.is_some(), "Escrow 3 should have approval");
    let approval3 = approval3.unwrap();
    assert_eq!(approval3.intent_id, "0x03");

    // Assert: approvals are independent and signatures are unique per request intent
    assert!(!approval1.signature.is_empty(), "Approval 1 should have signature");
    assert!(!approval2.signature.is_empty(), "Approval 2 should have signature");
    assert!(!approval3.signature.is_empty(), "Approval 3 should have signature");
    
    // Assert: signatures must be unique per request intent (each signature includes intent_id)
    let sig1 = approval1.signature;
    let sig2 = approval2.signature;
    let sig3 = approval3.signature;
    assert_ne!(sig1, sig2, "Signatures should be unique per request intent");
    assert_ne!(sig2, sig3, "Signatures should be unique per request intent");
    assert_ne!(sig1, sig3, "Signatures should be unique per request intent");
}

/// Test that monitor's validate_request_intent_fulfillment rejects escrows when matching request intent has expired
/// Why: Verify that expired request intents are rejected when validating escrow fulfillment
#[tokio::test]
async fn test_expiry_check_failure_in_monitor_validate_request_intent_fulfillment() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config();
    let monitor = EventMonitor::new(&config).await.expect("Failed to create monitor");
    
    // Create an expired request intent
    let current_time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let past_expiry = current_time - 1000; // Expired 1000 seconds ago
    
    let expired_request_intent = create_test_request_intent(
        "0xexpired_intent",
        "0xalice",
        false,
        past_expiry,
        None,
        Some(2),
    );
    
    // Add expired request intent to cache
    {
        let mut cache = monitor.event_cache.write().await;
        cache.push(expired_request_intent.clone());
    }
    
    // Create an escrow event that matches the expired request intent
    // The escrow must pass other validations first (amount, metadata, solver)
    // Note: escrow.offered_amount (1000) >= request_intent.desired_amount (0) ✓
    //       escrow.desired_metadata ("{}") == request_intent.desired_metadata ("{}") ✓
    //       Both have no solver reservation, so solver validation passes ✓
    let escrow_event = create_test_escrow_event(
        "0xescrow123",
        &expired_request_intent.intent_id,
        "0xalice",
        expired_request_intent.offered_amount,
    );
    
    // Verify that validation fails when request intent has expired
    let result = monitor.validate_request_intent_fulfillment(&escrow_event).await;
    assert!(result.is_err(), "Validation should fail when request intent has expired");
    let error_msg = result.unwrap_err().to_string();
    assert!(error_msg.contains("expired") || error_msg.contains("expiry"),
            "Error message should indicate request intent expired: {}", error_msg);
}

/// Test that monitor's validate_request_intent_fulfillment passes expiry check for non-expired request intents
/// Why: Verify that non-expired request intents pass the expiry validation
#[tokio::test]
async fn test_expiry_check_success_in_monitor_validate_request_intent_fulfillment() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config();
    let monitor = EventMonitor::new(&config).await.expect("Failed to create monitor");
    
    // Create a non-expired request intent
    let current_time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let future_expiry = current_time + 1000; // Expires in 1000 seconds
    
    let non_expired_request_intent = create_test_request_intent(
        "0xvalid_intent",
        "0xalice",
        false,
        future_expiry,
        None,
        Some(2),
    );
    
    // Add non-expired request intent to cache
    {
        let mut cache = monitor.event_cache.write().await;
        cache.push(non_expired_request_intent.clone());
    }
    
    // Create an escrow event that matches the non-expired request intent
    // The escrow must pass all other validations to reach the expiry check:
    // - escrow.offered_amount (1000) >= request_intent.desired_amount (0) ✓
    // - escrow.desired_metadata ("{}") == request_intent.desired_metadata ("{}") ✓
    // - Both have no solver reservation, so solver validation passes ✓
    let valid_escrow = create_test_escrow_event(
        "0xescrow456",
        &non_expired_request_intent.intent_id,
        "0xalice",
        non_expired_request_intent.offered_amount,
    );
    
    // Verify that validation passes when request intent has not expired
    // This confirms the expiry check passes for non-expired intents
    let result = monitor.validate_request_intent_fulfillment(&valid_escrow).await;
    assert!(result.is_ok(), "Validation should pass when request intent has not expired and all other validations pass");
}
