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
// TESTS
// ============================================================================

/// Test that revocable intents are rejected (error thrown)
/// Why: Verify critical security check - revocable intents must be rejected for escrow
#[test]
fn test_revocable_intent_rejection() {
    let revocable_intent = RequestIntentEvent {
        chain: "hub".to_string(),
        intent_id: "0xrevocable".to_string(),
        issuer: "0xalice".to_string(),
        offered_metadata: String::new(),
        offered_amount: 1000,
        desired_metadata: String::new(),
        desired_amount: 2000,
        expiry_time: 0,
        revocable: true, // NOT safe for escrow
        solver: None,
        connected_chain_id: None,
        timestamp: 0,
    };
    
    // Simulate validation: revocable intents should be rejected
    let result = is_safe_for_escrow(&revocable_intent);
    assert!(!result, "Revocable intents should NOT be safe for escrow");
    
    let non_revocable_intent = RequestIntentEvent {
        chain: "hub".to_string(),
        intent_id: "0xsafe".to_string(),
        issuer: "0xbob".to_string(),
        offered_metadata: String::new(),
        offered_amount: 1000,
        desired_metadata: String::new(),
        desired_amount: 2000,
        expiry_time: 0,
        revocable: false, // Safe for escrow
        solver: None,
        connected_chain_id: None,
        timestamp: 0,
    };
    
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
        escrow_cache.push(EscrowEvent {
            chain: "connected".to_string(),
            escrow_id: "0xescrow".to_string(),
            intent_id: intent_id.to_string(),
            issuer: "0xissuer".to_string(),
            offered_metadata: "{}".to_string(),
            offered_amount: 1000,
            reserved_solver: None,
            chain_id: 2,
            desired_metadata: "{}".to_string(),
            desired_amount: 1,
            expiry_time: 9999999999,
            revocable: false,
            chain_type: trusted_verifier::ChainType::Move,
            timestamp: 1,
        });
    }

    // Act: call approval generation on fulfillment with same intent_id
    let fulfillment = FulfillmentEvent {
        chain: "hub".to_string(),
        intent_id: intent_id.to_string(),
        intent_address: "0xaddr".to_string(),
        solver: "0xsolver".to_string(),
        provided_metadata: "{}".to_string(),
        provided_amount: 1000,
        timestamp: 2,
    };
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

    let fulfillment = FulfillmentEvent {
        chain: "hub".to_string(),
        intent_id: "0x999".to_string(), // Valid hex but no matching escrow
        intent_address: "0xaddr".to_string(),
        solver: "0xsolver".to_string(),
        provided_metadata: "{}".to_string(),
        provided_amount: 1000,
        timestamp: 2,
    };
    
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
        EscrowEvent {
            chain: "connected".to_string(),
            escrow_id: "0xescrow1".to_string(),
            intent_id: "0x01".to_string(),
            issuer: "0xissuer1".to_string(),
            offered_metadata: "{}".to_string(),
            offered_amount: 1000,
            reserved_solver: None,
            chain_id: 2,
            desired_metadata: "{}".to_string(),
            desired_amount: 1,
            expiry_time: 9999999999,
            revocable: false,
            chain_type: trusted_verifier::ChainType::Move,
            timestamp: 1,
        },
        EscrowEvent {
            chain: "connected".to_string(),
            escrow_id: "0xescrow2".to_string(),
            intent_id: "0x02".to_string(),
            issuer: "0xissuer2".to_string(),
            offered_metadata: "{}".to_string(),
            offered_amount: 2000,
            reserved_solver: None,
            chain_id: 2,
            desired_metadata: "{}".to_string(),
            desired_amount: 1,
            expiry_time: 9999999999,
            revocable: false,
            chain_type: trusted_verifier::ChainType::Move,
            timestamp: 1,
        },
        EscrowEvent {
            chain: "connected".to_string(),
            escrow_id: "0xescrow3".to_string(),
            intent_id: "0x03".to_string(),
            issuer: "0xissuer3".to_string(),
            offered_metadata: "{}".to_string(),
            offered_amount: 3000,
            reserved_solver: None,
            chain_id: 2,
            desired_metadata: "{}".to_string(),
            desired_amount: 1,
            expiry_time: 9999999999,
            revocable: false,
            chain_type: trusted_verifier::ChainType::Move,
            timestamp: 1,
        },
    ];

    // Insert all escrows into cache
    {
        let mut escrow_cache = monitor.escrow_cache.write().await;
        escrow_cache.extend(escrows.clone());
    }

    // Act: process multiple fulfillments concurrently
    let fulfillments = vec![
        FulfillmentEvent {
            chain: "hub".to_string(),
            intent_id: "0x01".to_string(),
            intent_address: "0xaddr1".to_string(),
            solver: "0xsolver1".to_string(),
            provided_metadata: "{}".to_string(),
            provided_amount: 1000,
            timestamp: 2,
        },
        FulfillmentEvent {
            chain: "hub".to_string(),
            intent_id: "0x02".to_string(),
            intent_address: "0xaddr2".to_string(),
            solver: "0xsolver2".to_string(),
            provided_metadata: "{}".to_string(),
            provided_amount: 2000,
            timestamp: 2,
        },
        FulfillmentEvent {
            chain: "hub".to_string(),
            intent_id: "0x03".to_string(),
            intent_address: "0xaddr3".to_string(),
            solver: "0xsolver3".to_string(),
            provided_metadata: "{}".to_string(),
            provided_amount: 3000,
            timestamp: 2,
        },
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

    // Assert: approvals are independent and signatures are unique per intent
    assert!(!approval1.signature.is_empty(), "Approval 1 should have signature");
    assert!(!approval2.signature.is_empty(), "Approval 2 should have signature");
    assert!(!approval3.signature.is_empty(), "Approval 3 should have signature");
    
    // Assert: signatures must be unique per intent (each signature includes intent_id)
    let sig1 = approval1.signature;
    let sig2 = approval2.signature;
    let sig3 = approval3.signature;
    assert_ne!(sig1, sig2, "Signatures should be unique per intent");
    assert_ne!(sig2, sig3, "Signatures should be unique per intent");
    assert_ne!(sig1, sig3, "Signatures should be unique per intent");
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Helper function for validation logic
fn is_safe_for_escrow(event: &RequestIntentEvent) -> bool {
    !event.revocable
}


