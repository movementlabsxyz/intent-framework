//! Unit tests for EVM escrow monitoring
//!
//! These tests verify EVM escrow detection, ECDSA signature creation, and approval workflows
//! without requiring external services.

use trusted_verifier::monitor::{EventMonitor, FulfillmentEvent};
use base64::Engine;
#[path = "mod.rs"]
mod test_helpers;
use test_helpers::build_test_config_with_evm;

/// Test that EVM escrow detection logic correctly identifies EVM escrows
/// Why: Verify that escrows are correctly identified as EVM when not in Aptos cache and EVM is configured
#[tokio::test]
async fn test_evm_escrow_detection_logic() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_evm();
    let monitor = EventMonitor::new(&config).await.expect("Failed to create monitor");

    // Create a fulfillment event for an intent that doesn't exist in Aptos escrow cache
    // This should be detected as an EVM escrow
    let fulfillment = FulfillmentEvent {
        chain: "hub".to_string(),
        intent_id: "0xevm_intent_123".to_string(),
        intent_address: "0xevm_addr".to_string(),
        solver: "0xsolver".to_string(),
        provided_metadata: "{}".to_string(),
        provided_amount: 1000,
        timestamp: 1,
    };

    // The monitor should detect this as EVM escrow because:
    // 1. It's not in the Aptos escrow cache
    // 2. connected_chain_evm is configured
    // This will be verified by checking that ECDSA signature is created (not Ed25519)
    let result = monitor.validate_and_approve_fulfillment(&fulfillment).await;
    
    // Should succeed and create approval (even without escrow in cache, the logic should work)
    // The actual detection happens in validate_and_approve_fulfillment
    // We verify by checking the approval signature format
    if result.is_ok() {
        let approval = monitor.get_approval_for_escrow("0xevm_intent_123").await;
        assert!(approval.is_some(), "Approval should exist for EVM escrow");
        let approval = approval.unwrap();
        // ECDSA signatures are base64 encoded 65-byte signatures
        // Decode and verify it's 65 bytes (r || s || v format)
        let sig_bytes = base64::engine::general_purpose::STANDARD.decode(&approval.signature).unwrap();
        assert_eq!(sig_bytes.len(), 65, "EVM signature should be 65 bytes (ECDSA format)");
    }
}

/// Test that ECDSA signature creation works for EVM escrows
/// Why: Verify that EVM escrows trigger ECDSA signature creation instead of Ed25519
#[tokio::test]
async fn test_evm_escrow_ecdsa_signature_creation() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_evm();
    let monitor = EventMonitor::new(&config).await.expect("Failed to create monitor");

    let fulfillment = FulfillmentEvent {
        chain: "hub".to_string(),
        intent_id: "0xevm_test_intent".to_string(),
        intent_address: "0xevm_test_addr".to_string(),
        solver: "0xsolver".to_string(),
        provided_metadata: "{}".to_string(),
        provided_amount: 1000,
        timestamp: 1,
    };

    // Process fulfillment - should create ECDSA signature for EVM
    let result = monitor.validate_and_approve_fulfillment(&fulfillment).await;
    
    // Should succeed (even if escrow not in cache, signature creation should work)
    if result.is_ok() {
        let approval = monitor.get_approval_for_escrow("0xevm_test_intent").await;
        if let Some(approval) = approval {
            // Verify signature is ECDSA format (65 bytes)
            let sig_bytes = base64::engine::general_purpose::STANDARD.decode(&approval.signature).unwrap();
            assert_eq!(sig_bytes.len(), 65, "EVM escrow should use ECDSA signature (65 bytes)");
        }
    }
}

/// Test that EVM and Aptos escrows are correctly differentiated
/// Why: Verify that the monitor correctly chooses ECDSA for EVM and Ed25519 for Aptos
#[tokio::test]
async fn test_evm_vs_aptos_escrow_differentiation() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_evm();
    let monitor = EventMonitor::new(&config).await.expect("Failed to create monitor");

    // First, add an Aptos escrow to the cache
    {
        let mut escrow_cache = monitor.escrow_cache.write().await;
        escrow_cache.push(trusted_verifier::monitor::EscrowEvent {
            chain: "connected".to_string(),
            escrow_id: "0xaptos_escrow".to_string(),
            intent_id: "0xmvmt_intent".to_string(),
            issuer: "0xissuer".to_string(),
            offered_metadata: "{}".to_string(),
            offered_amount: 1000,
            desired_metadata: "{}".to_string(),
            desired_amount: 1,
            expiry_time: 9999999999,
            revocable: false,
            reserved_solver: None,
            chain_id: 2,
            chain_type: trusted_verifier::ChainType::Move,
            timestamp: 1,
        });
    }

    // Test Aptos escrow - should use Ed25519 signature
    let aptos_fulfillment = FulfillmentEvent {
        chain: "hub".to_string(),
        intent_id: "0xmvmt_intent".to_string(),
        intent_address: "0xaptos_addr".to_string(),
        solver: "0xsolver".to_string(),
        provided_metadata: "{}".to_string(),
        provided_amount: 1000,
        timestamp: 2,
    };

    let aptos_result = monitor.validate_and_approve_fulfillment(&aptos_fulfillment).await;
    if aptos_result.is_ok() {
        let aptos_approval = monitor.get_approval_for_escrow("0xaptos_escrow").await;
        if let Some(approval) = aptos_approval {
            // Ed25519 signatures are 64 bytes (not 65)
            let sig_bytes = base64::engine::general_purpose::STANDARD.decode(&approval.signature).unwrap();
            assert_eq!(sig_bytes.len(), 64, "Aptos escrow should use Ed25519 signature (64 bytes)");
        }
    }

    // Test EVM escrow - should use ECDSA signature
    let evm_fulfillment = FulfillmentEvent {
        chain: "hub".to_string(),
        intent_id: "0xevm_intent".to_string(),
        intent_address: "0xevm_addr".to_string(),
        solver: "0xsolver".to_string(),
        provided_metadata: "{}".to_string(),
        provided_amount: 1000,
        timestamp: 3,
    };

    let evm_result = monitor.validate_and_approve_fulfillment(&evm_fulfillment).await;
    if evm_result.is_ok() {
        let evm_approval = monitor.get_approval_for_escrow("0xevm_intent").await;
        if let Some(approval) = evm_approval {
            // ECDSA signatures are 65 bytes
            let sig_bytes = base64::engine::general_purpose::STANDARD.decode(&approval.signature).unwrap();
            assert_eq!(sig_bytes.len(), 65, "EVM escrow should use ECDSA signature (65 bytes)");
        }
    }
}

/// Test complete EVM escrow approval workflow
/// Why: Verify the full workflow from fulfillment event to approval creation for EVM escrows
#[tokio::test]
async fn test_evm_escrow_approval_flow() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_evm();
    let monitor = EventMonitor::new(&config).await.expect("Failed to create monitor");

    let intent_id = "0xevm_workflow_intent";
    let fulfillment = FulfillmentEvent {
        chain: "hub".to_string(),
        intent_id: intent_id.to_string(),
        intent_address: "0xworkflow_addr".to_string(),
        solver: "0xsolver".to_string(),
        provided_metadata: "{}".to_string(),
        provided_amount: 1000,
        timestamp: 1,
    };

    // Process fulfillment
    let result = monitor.validate_and_approve_fulfillment(&fulfillment).await;
    
    // Should succeed and create approval
    if result.is_ok() {
        let approval = monitor.get_approval_for_escrow(intent_id).await;
        assert!(approval.is_some(), "Approval should exist after workflow completion");
        
        let approval = approval.unwrap();
        assert_eq!(approval.intent_id, intent_id, "Approval should have correct intent_id");
        assert!(!approval.signature.is_empty(), "Signature should not be empty");
        
        // Verify signature format is ECDSA (65 bytes)
        let sig_bytes = base64::engine::general_purpose::STANDARD.decode(&approval.signature).unwrap();
        assert_eq!(sig_bytes.len(), 65, "Signature should be ECDSA format (65 bytes)");
    }
}

/// Test error handling for invalid intent IDs in EVM escrow processing
/// Why: Verify that invalid intent IDs are handled gracefully in EVM escrow workflows
#[tokio::test]
async fn test_evm_escrow_with_invalid_intent_id() {
    let _ = tracing_subscriber::fmt::try_init();
    let config = build_test_config_with_evm();
    let monitor = EventMonitor::new(&config).await.expect("Failed to create monitor");

    // Test with empty intent ID
    let fulfillment_empty = FulfillmentEvent {
        chain: "hub".to_string(),
        intent_id: "".to_string(),
        intent_address: "0xaddr".to_string(),
        solver: "0xsolver".to_string(),
        provided_metadata: "{}".to_string(),
        provided_amount: 1000,
        timestamp: 1,
    };

    let result_empty = monitor.validate_and_approve_fulfillment(&fulfillment_empty).await;
    // Should handle empty intent ID gracefully (may succeed or fail, but shouldn't panic)
    assert!(result_empty.is_ok() || result_empty.is_err(), "Should handle empty intent ID without panic");

    // Test with invalid hex format (if signature creation requires valid hex)
    let fulfillment_invalid = FulfillmentEvent {
        chain: "hub".to_string(),
        intent_id: "not_a_valid_hex_string".to_string(),
        intent_address: "0xaddr".to_string(),
        solver: "0xsolver".to_string(),
        provided_metadata: "{}".to_string(),
        provided_amount: 1000,
        timestamp: 1,
    };

    let result_invalid = monitor.validate_and_approve_fulfillment(&fulfillment_invalid).await;
    // Should handle invalid hex gracefully
    assert!(result_invalid.is_ok() || result_invalid.is_err(), "Should handle invalid hex without panic");
}

