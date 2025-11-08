//! Unit tests for Aptos/Ed25519 cryptographic operations
//!
//! These tests verify Ed25519 signature functionality for Aptos chain compatibility.

use trusted_verifier::crypto::CryptoService;

#[path = "mod.rs"]
mod test_helpers;
use test_helpers::build_test_config;

/// Test that crypto service creates different key pairs for each instance
/// Why: Ensure each verifier instance has a unique cryptographic identity to prevent key collisions
#[test]
fn test_unique_key_generation() {
    let config1 = build_test_config();
    let config2 = build_test_config();
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
    let config = build_test_config();
    let service = CryptoService::new(&config).unwrap();
    
    // Create an approval signature
    let signature_data = service.create_approval_signature(true).unwrap();
    
    // Verify the signature
    let message = signature_data.approval_value.to_le_bytes();
    let is_valid = service.verify_signature(&message, &signature_data.signature).unwrap();
    
    assert!(is_valid, "Signature should be valid");
}

/// Test that incorrect signatures fail verification
/// Why: Prevent signature replay attacks - signatures must be tied to specific messages
#[test]
fn test_signature_verification_fails_for_wrong_message() {
    let config = build_test_config();
    let service = CryptoService::new(&config).unwrap();
    
    // Create signature for approval (value: 1)
    let signature_data = service.create_approval_signature(true).unwrap();
    
    // Try to verify with wrong message (rejection: value: 0)
    let wrong_message = 0u64.to_le_bytes();
    let is_valid = service.verify_signature(&wrong_message, &signature_data.signature).unwrap();
    
    assert!(!is_valid, "Signature should fail for wrong message");
}

/// Test that approval and rejection signatures are different
/// Why: Approval and rejection must be cryptographically distinct to prevent confusion
#[test]
fn test_approval_and_rejection_signatures_differ() {
    let config = build_test_config();
    let service = CryptoService::new(&config).unwrap();
    
    let approval_sig = service.create_approval_signature(true).unwrap();
    let rejection_sig = service.create_approval_signature(false).unwrap();
    
    // Signatures should be different
    assert_ne!(approval_sig.signature, rejection_sig.signature);
    // But approval values should be different
    assert_ne!(approval_sig.approval_value, rejection_sig.approval_value);
}

/// Test that escrow approval signature works
/// Why: Escrow operations require cryptographic authorization - signatures must be valid
#[test]
fn test_escrow_approval_signature() {
    let config = build_test_config();
    let service = CryptoService::new(&config).unwrap();
    
    // Create escrow approval signature
    let signature_data = service.create_escrow_approval_signature(true).unwrap();
    
    // Verify the signature
    let message = signature_data.approval_value.to_le_bytes();
    let is_valid = service.verify_signature(&message, &signature_data.signature).unwrap();
    
    assert!(is_valid, "Escrow signature should be valid");
}

/// Test that public key is consistent
/// Why: Public key must remain constant for the same instance for external verification
#[test]
fn test_public_key_consistency() {
    let config = build_test_config();
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
    let config = build_test_config();
    let service = CryptoService::new(&config).unwrap();
    
    let signature_data = service.create_approval_signature(true).unwrap();
    
    // Timestamp should be non-zero and reasonable (within last hour)
    assert!(signature_data.timestamp > 0, "Timestamp should be non-zero");
    
    let now = chrono::Utc::now().timestamp() as u64;
    assert!(signature_data.timestamp <= now, "Timestamp should be in the past");
    assert!(signature_data.timestamp >= now - 3600, "Timestamp should be recent");
}

/// Test that approval_value is correct for approval signatures
/// Why: Approval value (1) must be correct for downstream systems to authorize transactions
#[test]
fn test_approval_value_true() {
    let config = build_test_config();
    let service = CryptoService::new(&config).unwrap();
    
    let sig = service.create_approval_signature(true).unwrap();
    assert_eq!(sig.approval_value, 1);
}

/// Test that approval_value is correct for rejection signatures
/// Why: Rejection value (0) must be correct to properly deny invalid transactions
#[test]
fn test_approval_value_false() {
    let config = build_test_config();
    let service = CryptoService::new(&config).unwrap();
    
    let sig = service.create_approval_signature(false).unwrap();
    assert_eq!(sig.approval_value, 0);
}

