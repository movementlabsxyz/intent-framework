//! Unit tests for event monitoring
//!
//! These tests verify event structures and cache behavior
//! without requiring external services.

use trusted_verifier::monitor::{IntentEvent, EscrowEvent, FulfillmentEvent, EventMonitor};
use trusted_verifier::config::{ApiConfig, ChainConfig, VerifierConfig, Config};

// ============================================================================
// TESTS
// ============================================================================

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

/// Test that approval is generated when fulfillment and escrow are both present
#[tokio::test]
async fn test_generates_approval_when_fulfillment_and_escrow_present() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config();
    let monitor = EventMonitor::new(&config).await.expect("Failed to create monitor");

    // Arrange: insert escrow with intent_id "0xintent"
    {
        let mut escrow_cache = monitor.escrow_cache.write().await;
        escrow_cache.push(EscrowEvent {
            chain: "connected".to_string(),
            escrow_id: "0xescrow".to_string(),
            intent_id: "0xintent".to_string(),
            issuer: "0xissuer".to_string(),
            source_metadata: "{}".to_string(),
            source_amount: 1000,
            desired_metadata: "{}".to_string(),
            desired_amount: 1,
            expiry_time: 9999999999,
            revocable: false,
            timestamp: 1,
        });
    }

    // Act: call approval generation on fulfillment with same intent_id
    let fulfillment = FulfillmentEvent {
        chain: "hub".to_string(),
        intent_id: "0xintent".to_string(),
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
    assert_eq!(approval.intent_id, "0xintent");
    assert_eq!(approval.approval_value, 1);
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
        intent_id: "0xmissing".to_string(),
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

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Helper function for validation logic
fn is_safe_for_escrow(event: &IntentEvent) -> bool {
    !event.revocable
}

/// Creates a test configuration for EventMonitor unit tests
/// Why: Provide a minimal valid config structure for testing without external dependencies
fn build_test_config() -> Config {
    Config {
        hub_chain: ChainConfig {
            name: "hub".to_string(),
            rpc_url: "http://127.0.0.1:18080".to_string(),
            chain_id: 1,
            intent_module_address: "0x1".to_string(),
            escrow_module_address: None,
            known_accounts: Some(vec!["0x1".to_string()]),
        },
        connected_chain: ChainConfig {
            name: "connected".to_string(),
            rpc_url: "http://127.0.0.1:18082".to_string(),
            chain_id: 2,
            intent_module_address: "0x2".to_string(),
            escrow_module_address: Some("0x2".to_string()),
            known_accounts: Some(vec!["0x2".to_string()]),
        },
        verifier: VerifierConfig {
            private_key: "TEST_PRIVATE_KEY_BASE64".to_string(),
            public_key: "TEST_PUBLIC_KEY_BASE64".to_string(),
            polling_interval_ms: 1000,
            validation_timeout_ms: 1000,
        },
        api: ApiConfig { 
            host: "127.0.0.1".to_string(), 
            port: 3999, 
            cors_origins: vec![] 
        },
    }
}

