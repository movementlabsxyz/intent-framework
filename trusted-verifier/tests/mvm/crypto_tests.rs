//! Unit tests for Move VM/Ed25519 cryptographic operations
//!
//! These tests verify Ed25519 signature functionality for Move VM chain compatibility.

use trusted_verifier::crypto::CryptoService;

#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::{build_test_config_with_mvm, create_base_fulfillment};

/// Test that crypto service creates different key pairs for each instance
/// Why: Ensure each verifier instance has a unique cryptographic identity to prevent key collisions
#[test]
fn test_unique_key_generation() {
    let config1 = build_test_config_with_mvm();
    let config2 = build_test_config_with_mvm();
    let service1 = CryptoService::new(&config1).unwrap();
    let service2 = CryptoService::new(&config2).unwrap();

    let public_key1 = service1.get_public_key();
    let public_key2 = service2.get_public_key();

    // Each instance should have a different key
    assert_ne!(public_key1, public_key2);
}

/// Test that signatures can be created and verified
/// Why: Cryptographic signatures are the core security mechanism - must work correctly
#[test]
fn test_signature_creation_and_verification() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    // Create an approval signature (signs intent_id)
    let intent_id = "0x01";
    let signature_data = service.create_mvm_approval_signature(intent_id).unwrap();

    // Verify the signature - reconstruct message from intent_id
    let intent_id_hex = intent_id.strip_prefix("0x").unwrap_or(intent_id);
    let intent_id_bytes = hex::decode(intent_id_hex).unwrap();
    let mut intent_id_padded = [0u8; 32];
    intent_id_padded[32 - intent_id_bytes.len()..].copy_from_slice(&intent_id_bytes);
    let message = bcs::to_bytes(&intent_id_padded).unwrap();
    let is_valid = service
        .verify_signature(&message, &signature_data.signature)
        .unwrap();

    assert!(is_valid, "Signature should be valid");
}

/// Test that incorrect signatures fail verification
/// Why: Prevent signature replay attacks - signatures must be tied to specific intent_ids
#[test]
fn test_signature_verification_fails_for_wrong_message() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    // Create signature for intent_id
    let intent_id = "0x01";
    let signature_data = service.create_mvm_approval_signature(intent_id).unwrap();

    // Try to verify with wrong intent_id
    let wrong_intent_id = "0x02";
    let wrong_intent_id_hex = wrong_intent_id
        .strip_prefix("0x")
        .unwrap_or(wrong_intent_id);
    let wrong_intent_id_bytes = hex::decode(wrong_intent_id_hex).unwrap();
    let mut wrong_intent_id_padded = [0u8; 32];
    wrong_intent_id_padded[32 - wrong_intent_id_bytes.len()..]
        .copy_from_slice(&wrong_intent_id_bytes);
    let wrong_message = bcs::to_bytes(&wrong_intent_id_padded).unwrap();
    let is_valid = service
        .verify_signature(&wrong_message, &signature_data.signature)
        .unwrap();

    assert!(!is_valid, "Signature should fail for wrong intent_id");
}

/// Test that signatures for different intent_ids are different
/// Why: Each intent_id must have a unique signature to prevent replay attacks
#[test]
fn test_signatures_differ_for_different_intent_ids() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    let intent_id1 = "0x01";
    let intent_id2 = "0x02";
    let sig1 = service.create_mvm_approval_signature(intent_id1).unwrap();
    let sig2 = service.create_mvm_approval_signature(intent_id2).unwrap();

    // Signatures should be different (they sign different intent_ids)
    assert_ne!(sig1.signature, sig2.signature);
}

/// Test that escrow approval signature works
/// Why: Escrow operations require cryptographic authorization - signatures must be valid
#[test]
fn test_escrow_approval_signature() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    // Create escrow approval signature (signs intent_id)
    let intent_id = "0x01";
    let signature_data = service.create_mvm_approval_signature(intent_id).unwrap();

    // Verify the signature - reconstruct message from intent_id
    let intent_id_hex = intent_id.strip_prefix("0x").unwrap_or(intent_id);
    let intent_id_bytes = hex::decode(intent_id_hex).unwrap();
    let mut intent_id_padded = [0u8; 32];
    intent_id_padded[32 - intent_id_bytes.len()..].copy_from_slice(&intent_id_bytes);
    let message = bcs::to_bytes(&intent_id_padded).unwrap();
    let is_valid = service
        .verify_signature(&message, &signature_data.signature)
        .unwrap();

    assert!(is_valid, "Escrow signature should be valid");
}

/// Test that public key is consistent
/// Why: Public key must remain constant for the same instance for external verification
#[test]
fn test_public_key_consistency() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    let public_key1 = service.get_public_key();
    let public_key2 = service.get_public_key();

    // Public key should be the same for the same instance
    assert_eq!(public_key1, public_key2);
}

/// Test that signature contains timestamp
/// Why: Timestamps enable replay attack prevention and audit trail for approval decisions
#[test]
fn test_signature_contains_timestamp() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    let intent_id = "0x01";
    let signature_data = service.create_mvm_approval_signature(intent_id).unwrap();

    // Timestamp should be non-zero and reasonable (within last hour)
    assert!(signature_data.timestamp > 0, "Timestamp should be non-zero");

    let now = chrono::Utc::now().timestamp() as u64;
    assert!(
        signature_data.timestamp <= now,
        "Timestamp should be in the past"
    );
    assert!(
        signature_data.timestamp >= now - 3600,
        "Timestamp should be recent"
    );
}

/// Test intent ID validation for signature creation
/// Why: Valid intent IDs should succeed, invalid intent IDs should be rejected with clear error messages
#[test]
fn test_mvm_signature_intent_id_validation() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    // Test with valid intent ID from base helper (should succeed)
    let base_fulfillment = create_base_fulfillment();
    let valid_intent_id = &base_fulfillment.intent_id;
    let result = service.create_mvm_approval_signature(valid_intent_id);
    assert!(
        result.is_ok(),
        "Should accept valid intent ID from base helper with even number of hex digits"
    );

    // Test with intent ID that has odd number of hex digits (now valid after padding)
    let odd_digits_intent_id = "0x123";
    let result = service.create_mvm_approval_signature(odd_digits_intent_id);
    assert!(
        result.is_ok(),
        "Should accept intent ID with odd number of hex digits after padding"
    );

    // Test with invalid hex string (non-hex characters)
    let invalid_hex = "0xinvalid_hex_string";
    let result = service.create_mvm_approval_signature(invalid_hex);
    assert!(result.is_err(), "Should reject invalid hex string");

    let error_msg = result.unwrap_err().to_string();
    assert!(
        error_msg.contains("Invalid intent_id hex"),
        "Error message should indicate invalid hex format: {}",
        error_msg
    );
}
