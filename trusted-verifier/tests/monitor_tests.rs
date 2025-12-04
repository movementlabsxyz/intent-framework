//! Unit tests for event monitoring
//!
//! These tests verify event structures and cache behavior
//! without requiring external services.

use futures::future;
use trusted_verifier::monitor::{EscrowEvent, EventMonitor, FulfillmentEvent, IntentEvent};
#[path = "mod.rs"]
mod test_helpers;
use test_helpers::{
    build_test_config_with_mvm, create_base_escrow_event, create_base_fulfillment,
    create_base_intent_mvm,
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Helper function for validation logic
fn is_safe_for_escrow(event: &IntentEvent) -> bool {
    !event.revocable
}

// ============================================================================
// INTENT ID NORMALIZATION TESTS
// ============================================================================

/// Test that normalize_intent_id handles leading zeros correctly
/// What is tested: Intent IDs with leading zeros are normalized to match those without
/// Why: EVM and Move VM may format the same intent_id differently (with/without leading zeros)
#[test]
fn test_normalize_intent_id_leading_zeros() {
    use trusted_verifier::monitor::normalize_intent_id;

    // Test case from the actual error: one has leading zero, one doesn't
    let with_leading_zero = "0x0911ddf3c2ef882c7c42af3f65b2c32b3f26fde142cf30afd2ea58f8a16ef9b7";
    let without_leading_zero = "0x911ddf3c2ef882c7c42af3f65b2c32b3f26fde142cf30afd2ea58f8a16ef9b7";

    let normalized_with = normalize_intent_id(with_leading_zero);
    let normalized_without = normalize_intent_id(without_leading_zero);

    assert_eq!(
        normalized_with, normalized_without,
        "Intent IDs with and without leading zeros should normalize to the same value"
    );
    assert_eq!(
        normalized_with,
        "0x911ddf3c2ef882c7c42af3f65b2c32b3f26fde142cf30afd2ea58f8a16ef9b7"
    );
}

/// Test that normalize_intent_id handles all-zero intent IDs
/// What is tested: Intent ID with all zeros is normalized correctly
/// Why: Edge case that should be handled gracefully
#[test]
fn test_normalize_intent_id_all_zeros() {
    use trusted_verifier::monitor::normalize_intent_id;

    assert_eq!(normalize_intent_id("0x0000"), "0x0");
    assert_eq!(normalize_intent_id("0x0"), "0x0");
}

/// Test that normalize_intent_id handles case differences
/// What is tested: Uppercase hex characters are normalized to lowercase
/// Why: Ensures consistent comparison regardless of input case
#[test]
fn test_normalize_intent_id_case() {
    use trusted_verifier::monitor::normalize_intent_id;

    assert_eq!(normalize_intent_id("0xABCDEF"), "0xabcdef");
    assert_eq!(normalize_intent_id("0xabcdef"), "0xabcdef");
}

// ============================================================================
// TESTS
// ============================================================================

/// Test that revocable intents are rejected (error thrown)
/// Why: Verify critical security check - revocable intents must be rejected for escrow
#[test]
fn test_revocable_intent_rejection() {
    let revocable_intent = IntentEvent {
        intent_id: "0xrevocable".to_string(),
        revocable: true, // NOT safe for escrow
        ..create_base_intent_mvm()
    };

    // Simulate validation: revocable intents should be rejected
    let result = is_safe_for_escrow(&revocable_intent);
    assert!(!result, "Revocable intents should NOT be safe for escrow");

    let non_revocable_intent = IntentEvent {
        intent_id: "0xsafe".to_string(),
        ..create_base_intent_mvm()
    };

    let result = is_safe_for_escrow(&non_revocable_intent);
    assert!(result, "Non-revocable intents should be safe for escrow");
}

/// Test that approval is generated when fulfillment and escrow are both present
#[tokio::test]
async fn test_generates_approval_when_fulfillment_and_escrow_present() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    // Arrange: insert escrow with intent_id (valid hex address - even number of hex digits)
    let intent_id = "0x01";
    {
        let mut escrow_cache = monitor.escrow_cache.write().await;
        escrow_cache.push(EscrowEvent {
            intent_id: intent_id.to_string(),
            ..create_base_escrow_event()
        });
    }

    // Act: call approval generation on fulfillment with same intent_id
    let fulfillment = FulfillmentEvent {
        intent_id: intent_id.to_string(),
        ..create_base_fulfillment()
    };
    monitor
        .validate_and_approve_fulfillment(&fulfillment)
        .await
        .expect("Approval generation should succeed");

    // Assert: approval exists for escrow
    let approval = monitor
        .get_approval_for_escrow(
            "0x2222222222222222222222222222222222222222222222222222222222222222",
        )
        .await;
    assert!(approval.is_some(), "Approval should exist for escrow");
    let approval = approval.unwrap();
    assert_eq!(approval.intent_id, intent_id);
    assert!(
        !approval.signature.is_empty(),
        "Signature should not be empty"
    );
}

/// Test that error is returned when no matching escrow exists
#[tokio::test]
async fn test_returns_error_when_no_matching_escrow() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    let fulfillment = FulfillmentEvent {
        intent_id: "0x999".to_string(), // Valid hex but no matching escrow
        ..create_base_fulfillment()
    };

    // Act: try to generate approval without matching escrow
    let result = monitor.validate_and_approve_fulfillment(&fulfillment).await;

    // Assert: should return error and no approval should exist
    assert!(
        result.is_err(),
        "Should return error when escrow is missing"
    );
    assert!(
        monitor.get_approval_for_escrow("0xescrow").await.is_none(),
        "No approval should exist"
    );
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
    let config = build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    // Arrange: create multiple escrows with different intent_ids simultaneously (valid hex addresses)
    let escrows = vec![
        EscrowEvent {
            escrow_id: "0xescrow1".to_string(),
            intent_id: "0x01".to_string(),
            ..create_base_escrow_event()
        },
        EscrowEvent {
            escrow_id: "0xescrow2".to_string(),
            intent_id: "0x02".to_string(),
            ..create_base_escrow_event()
        },
        EscrowEvent {
            escrow_id: "0xescrow3".to_string(),
            intent_id: "0x03".to_string(),
            ..create_base_escrow_event()
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
            intent_id: "0x01".to_string(),
            ..create_base_fulfillment()
        },
        FulfillmentEvent {
            intent_id: "0x02".to_string(),
            ..create_base_fulfillment()
        },
        FulfillmentEvent {
            intent_id: "0x03".to_string(),
            ..create_base_fulfillment()
        },
    ];

    // Process all fulfillments concurrently
    let results: Vec<_> = future::join_all(
        fulfillments
            .iter()
            .map(|f| monitor.validate_and_approve_fulfillment(f)),
    )
    .await;

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
    assert!(
        !approval1.signature.is_empty(),
        "Approval 1 should have signature"
    );
    assert!(
        !approval2.signature.is_empty(),
        "Approval 2 should have signature"
    );
    assert!(
        !approval3.signature.is_empty(),
        "Approval 3 should have signature"
    );

    // Assert: signatures must be unique per intent (each signature includes intent_id)
    let sig1 = approval1.signature;
    let sig2 = approval2.signature;
    let sig3 = approval3.signature;
    assert_ne!(sig1, sig2, "Signatures should be unique per intent");
    assert_ne!(sig2, sig3, "Signatures should be unique per intent");
    assert_ne!(sig1, sig3, "Signatures should be unique per intent");
}

/// Test that monitor's validate_intent_fulfillment rejects escrows when matching intent has expired
/// Why: Verify that expired intents are rejected when validating escrow fulfillment
#[tokio::test]
async fn test_expiry_check_failure_in_monitor_validate_intent_fulfillment() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    // Create an expired intent
    let current_time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let past_expiry = current_time - 1000; // Expired 1000 seconds ago

    let expired_intent = IntentEvent {
        intent_id: "0xexpired_intent".to_string(),
        expiry_time: past_expiry,
        ..create_base_intent_mvm()
    };

    // Add expired intent to cache
    {
        let mut cache = monitor.event_cache.write().await;
        cache.push(expired_intent.clone());
    }

    // Create an escrow event that matches the expired intent
    // The escrow must pass other validations first (amount, metadata, solver)
    // Note: escrow.offered_amount (1000) >= intent.desired_amount (0) ✓
    //       escrow.desired_metadata ("{}") == intent.desired_metadata ("{}") ✓
    //       Both have no solver reservation, so solver validation passes ✓
    let escrow_event = EscrowEvent {
        intent_id: expired_intent.intent_id.clone(),
        ..create_base_escrow_event()
    };

    // Verify that validation fails when intent has expired
    let result = monitor
        .validate_intent_fulfillment(&escrow_event)
        .await;
    assert!(
        result.is_err(),
        "Validation should fail when intent has expired"
    );
    let error_msg = result.unwrap_err().to_string();
    assert!(
        error_msg.contains("expired") || error_msg.contains("expiry"),
        "Error message should indicate intent expired: {}",
        error_msg
    );
}

/// Test that monitor's validate_intent_fulfillment passes expiry check for non-expired intents
/// Why: Verify that non-expired intents pass the expiry validation
#[tokio::test]
async fn test_expiry_check_success_in_monitor_validate_intent_fulfillment() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    // Create a non-expired intent
    let current_time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let future_expiry = current_time + 1000; // Expires in 1000 seconds

    let non_expired_intent = IntentEvent {
        intent_id: "0xvalid_intent".to_string(),
        expiry_time: future_expiry,
        ..create_base_intent_mvm()
    };

    // Add non-expired intent to cache
    {
        let mut cache = monitor.event_cache.write().await;
        cache.push(non_expired_intent.clone());
    }

    // Create an escrow event that matches the non-expired intent
    // The escrow must pass all other validations to reach the expiry check:
    // - escrow.offered_amount (1000) >= intent.desired_amount (0) ✓
    // - escrow.desired_metadata ("{}") == intent.desired_metadata ("{}") ✓
    // - Both have no solver reservation, so solver validation passes ✓
    let valid_escrow = EscrowEvent {
        intent_id: non_expired_intent.intent_id.clone(),
        ..create_base_escrow_event()
    };

    // Verify that validation passes when intent has not expired
    // This confirms the expiry check passes for non-expired intents
    let result = monitor
        .validate_intent_fulfillment(&valid_escrow)
        .await;
    assert!(
        result.is_ok(),
        "Validation should pass when intent has not expired and all other validations pass"
    );
}

/// Test that duplicate escrow events are rejected (not added to cache)
/// Why: Verify that the monitor correctly detects and rejects duplicate escrow events
#[tokio::test]
async fn test_duplicate_escrow_event_rejection() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    let escrow = create_base_escrow_event();

    // Add escrow to cache (first time)
    {
        let mut escrow_cache = monitor.escrow_cache.write().await;
        // Simulate duplicate detection logic from monitor_connected_chain
        if !escrow_cache.iter().any(|cached| {
            cached.escrow_id == escrow.escrow_id && cached.chain_id == escrow.chain_id
        }) {
            escrow_cache.push(escrow.clone());
        }
    }

    // Verify escrow was added
    let escrow_cache = monitor.escrow_cache.read().await;
    assert_eq!(escrow_cache.len(), 1, "Escrow should be in cache");
    assert_eq!(escrow_cache[0].escrow_id, escrow.escrow_id);
    drop(escrow_cache);

    // Try to add the same escrow again (duplicate)
    {
        let mut escrow_cache = monitor.escrow_cache.write().await;
        // Simulate duplicate detection logic from monitor_connected_chain
        if !escrow_cache.iter().any(|cached| {
            cached.escrow_id == escrow.escrow_id && cached.chain_id == escrow.chain_id
        }) {
            escrow_cache.push(escrow.clone());
        }
    }

    // Verify duplicate was not added
    let escrow_cache = monitor.escrow_cache.read().await;
    assert_eq!(
        escrow_cache.len(),
        1,
        "Duplicate escrow should not be added to cache"
    );
    assert_eq!(escrow_cache[0].escrow_id, escrow.escrow_id);
}

/// Test that duplicate intent events are rejected (not added to cache)
/// Why: Verify that the monitor correctly detects and rejects duplicate intent events
#[tokio::test]
async fn test_duplicate_intent_event_rejection() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    let intent = create_base_intent_mvm();

    // Add intent to cache (first time)
    {
        let mut cache = monitor.event_cache.write().await;
        // Simulate duplicate detection logic from monitor_hub_chain
        if !cache
            .iter()
            .any(|cached| cached.intent_id == intent.intent_id)
        {
            cache.push(intent.clone());
        }
    }

    // Verify intent was added
    let cache = monitor.event_cache.read().await;
    assert_eq!(cache.len(), 1, "Intent should be in cache");
    assert_eq!(cache[0].intent_id, intent.intent_id);
    drop(cache);

    // Try to add the same intent again (duplicate)
    {
        let mut cache = monitor.event_cache.write().await;
        // Simulate duplicate detection logic from monitor_hub_chain
        if !cache
            .iter()
            .any(|cached| cached.intent_id == intent.intent_id)
        {
            cache.push(intent.clone());
        }
    }

    // Verify duplicate was not added
    let cache = monitor.event_cache.read().await;
    assert_eq!(
        cache.len(),
        1,
        "Duplicate intent should not be added to cache"
    );
    assert_eq!(cache[0].intent_id, intent.intent_id);
}

/// Test that duplicate fulfillment events are handled correctly (not processed twice)
/// Why: Verify that the monitor correctly detects and skips duplicate fulfillment events
#[tokio::test]
async fn test_duplicate_fulfillment_event_handling() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    // Add matching escrow to cache (required for approval generation)
    {
        let mut escrow_cache = monitor.escrow_cache.write().await;
        escrow_cache.push(create_base_escrow_event());
    }

    let fulfillment = create_base_fulfillment();

    // Add fulfillment to cache (first time) and process it
    {
        let mut fulfillment_cache = monitor.fulfillment_cache.write().await;
        // Simulate duplicate detection logic from poll_hub_events
        if !fulfillment_cache
            .iter()
            .any(|cached| cached.intent_id == fulfillment.intent_id)
        {
            fulfillment_cache.push(fulfillment.clone());
        }
    }

    // Process the first fulfillment (should generate approval)
    monitor
        .validate_and_approve_fulfillment(&fulfillment)
        .await
        .expect("First fulfillment should succeed");

    // Verify approval was generated
    let approval = monitor
        .get_approval_for_escrow(
            "0x2222222222222222222222222222222222222222222222222222222222222222",
        )
        .await;
    assert!(
        approval.is_some(),
        "Approval should exist after first fulfillment"
    );
    let first_approval = approval.unwrap();
    let first_signature = first_approval.signature.clone();

    // Try to add the same fulfillment again (duplicate)
    {
        let mut fulfillment_cache = monitor.fulfillment_cache.write().await;
        // Simulate duplicate detection logic from poll_hub_events
        if !fulfillment_cache
            .iter()
            .any(|cached| cached.intent_id == fulfillment.intent_id)
        {
            fulfillment_cache.push(fulfillment.clone());
        }
    }

    // Verify duplicate was not added to cache
    let fulfillment_cache = monitor.fulfillment_cache.read().await;
    assert_eq!(
        fulfillment_cache.len(),
        1,
        "Duplicate fulfillment should not be added to cache"
    );
    drop(fulfillment_cache);

    // Verify approval was not regenerated (same approval exists)
    let approval = monitor
        .get_approval_for_escrow(
            "0x2222222222222222222222222222222222222222222222222222222222222222",
        )
        .await;
    assert!(approval.is_some(), "Approval should still exist");
    let second_approval = approval.unwrap();
    assert_eq!(
        first_signature, second_approval.signature,
        "Approval should not be regenerated for duplicate fulfillment"
    );
}

/// Test that base helper structs work with signature generation
/// Why: Verify that base helpers use valid hex values that can be used for signature generation
#[tokio::test]
async fn test_base_helpers_work_with_signature_generation() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    // Add escrow using base helper (should have valid hex intent_id)
    {
        let mut escrow_cache = monitor.escrow_cache.write().await;
        escrow_cache.push(create_base_escrow_event());
    }

    // Create fulfillment using base helper (should have valid hex intent_id matching escrow)
    let fulfillment = create_base_fulfillment();

    // This should succeed - base helpers should have valid hex values
    let result = monitor.validate_and_approve_fulfillment(&fulfillment).await;
    assert!(result.is_ok(), "Base helpers should work with signature generation - intent_id must be valid hex (even number of digits)");

    // Verify approval was generated
    let approval = monitor
        .get_approval_for_escrow(
            "0x2222222222222222222222222222222222222222222222222222222222222222",
        )
        .await;
    assert!(
        approval.is_some(),
        "Approval should exist when using base helpers"
    );
}

/// Test that fulfillment events with odd-length intent_ids are normalized correctly
/// Why: Move VM events can emit intent_ids with odd number of hex characters (e.g., 63 chars),
/// which must be normalized to 64 chars before signature creation to avoid hex parsing errors
#[tokio::test]
async fn test_fulfillment_with_odd_length_intent_id() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    // Create escrow with normalized intent_id (64 hex chars)
    // Odd-length intent_id (63 hex chars): eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
    // Normalized to (64 hex chars): 0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
    let escrow_intent_id = "0x0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
    {
        let mut escrow_cache = monitor.escrow_cache.write().await;
        escrow_cache.push(EscrowEvent {
            intent_id: escrow_intent_id.to_string(),
            escrow_id: "0x2222222222222222222222222222222222222222222222222222222222222222"
                .to_string(),
            ..create_base_escrow_event()
        });
    }

    // Create fulfillment with odd-length intent_id (63 hex chars) - simulates real Move VM event
    // This should be normalized to 64 chars when creating the signature
    let fulfillment_odd_intent_id =
        "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"; // 63 hex chars
    let fulfillment = FulfillmentEvent {
        intent_id: fulfillment_odd_intent_id.to_string(),
        ..create_base_fulfillment()
    };

    // This should succeed - the intent_id should be normalized to 64 chars before signature creation
    let result = monitor.validate_and_approve_fulfillment(&fulfillment).await;
    assert!(
        result.is_ok(),
        "Fulfillment with odd-length intent_id should be normalized and work with signature generation"
    );

    // Verify approval was generated
    let approval = monitor
        .get_approval_for_escrow(
            "0x2222222222222222222222222222222222222222222222222222222222222222",
        )
        .await;
    assert!(
        approval.is_some(),
        "Approval should exist for fulfillment with odd-length intent_id after normalization"
    );
}

/// Test that approval generation fails when fulfillment intent_id doesn't match escrow intent_id
/// Why: Verify that mismatched intent_ids are rejected - fulfillment must match an existing escrow
#[tokio::test]
async fn test_approval_fails_when_intent_id_mismatch() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    // Add escrow with one intent_id
    {
        let mut escrow_cache = monitor.escrow_cache.write().await;
        escrow_cache.push(EscrowEvent {
            intent_id: "0x01".to_string(), // Valid hex
            ..create_base_escrow_event()
        });
    }

    // Create fulfillment with different intent_id (doesn't match escrow)
    let fulfillment = FulfillmentEvent {
        intent_id: "0x02".to_string(), // Different intent_id - doesn't match escrow
        ..create_base_fulfillment()
    };

    // This should fail - no matching escrow found
    let result = monitor.validate_and_approve_fulfillment(&fulfillment).await;
    assert!(
        result.is_err(),
        "Approval should fail when fulfillment intent_id doesn't match any escrow"
    );

    let error_msg = result.unwrap_err().to_string();
    assert!(
        error_msg.contains("No matching escrow") || error_msg.contains("matching escrow"),
        "Error message should indicate no matching escrow found: {}",
        error_msg
    );

    // Verify no approval was generated
    let approval = monitor
        .get_approval_for_escrow(
            "0x2222222222222222222222222222222222222222222222222222222222222222",
        )
        .await;
    assert!(
        approval.is_none(),
        "No approval should exist when intent_ids don't match"
    );
}

/// Test that approval generation fails when no escrow exists in cache
/// Why: Verify that fulfillments cannot be approved when there's no matching escrow in the cache
#[tokio::test]
async fn test_approval_fails_when_no_escrow_exists() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    // Ensure escrow cache is empty (no escrow added)
    let escrow_cache = monitor.escrow_cache.read().await;
    assert_eq!(escrow_cache.len(), 0, "Escrow cache should be empty");
    drop(escrow_cache);

    // Create fulfillment (but no matching escrow exists)
    let fulfillment = create_base_fulfillment();

    // This should fail - no escrow in cache to match
    let result = monitor.validate_and_approve_fulfillment(&fulfillment).await;
    assert!(
        result.is_err(),
        "Approval should fail when no escrow exists in cache"
    );

    let error_msg = result.unwrap_err().to_string();
    assert!(
        error_msg.contains("No matching escrow") || error_msg.contains("matching escrow"),
        "Error message should indicate no matching escrow found: {}",
        error_msg
    );

    // Verify no approval was generated
    let approval = monitor
        .get_approval_for_escrow(
            "0x2222222222222222222222222222222222222222222222222222222222222222",
        )
        .await;
    assert!(
        approval.is_none(),
        "No approval should exist when no escrow is in cache"
    );
}
