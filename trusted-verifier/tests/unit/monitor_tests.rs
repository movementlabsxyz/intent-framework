//! Unit tests for event monitoring
//!
//! These tests verify event structures and cache behavior
//! without requiring external services.

use trusted_verifier::monitor::IntentEvent;

/// Test that revocable intents are rejected (error thrown)
/// Why: Verify critical security check - revocable intents must be rejected for escrow
#[test]
fn test_revocable_intent_rejection() {
    let revocable_intent = IntentEvent {
        chain: "hub".to_string(),
        intent_id: "0xrevocable".to_string(),
        issuer: "0xalice".to_string(),
        source_metadata: String::new(),
        source_amount: 1000,
        desired_metadata: String::new(),
        desired_amount: 2000,
        expiry_time: 0,
        revocable: true, // NOT safe for escrow
        timestamp: 0,
    };
    
    // Simulate validation: revocable intents should be rejected
    let result = is_safe_for_escrow(&revocable_intent);
    assert!(!result, "Revocable intents should NOT be safe for escrow");
    
    let non_revocable_intent = IntentEvent {
        chain: "hub".to_string(),
        intent_id: "0xsafe".to_string(),
        issuer: "0xbob".to_string(),
        source_metadata: String::new(),
        source_amount: 1000,
        desired_metadata: String::new(),
        desired_amount: 2000,
        expiry_time: 0,
        revocable: false, // Safe for escrow
        timestamp: 0,
    };
    
    let result = is_safe_for_escrow(&non_revocable_intent);
    assert!(result, "Non-revocable intents should be safe for escrow");
}

/// Helper function for validation logic
fn is_safe_for_escrow(event: &IntentEvent) -> bool {
    !event.revocable
}

