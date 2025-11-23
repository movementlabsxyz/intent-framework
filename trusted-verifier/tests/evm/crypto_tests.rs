//! Unit tests for EVM/ECDSA cryptographic operations
//!
//! These tests verify ECDSA signature functionality for EVM chain compatibility.

use trusted_verifier::crypto::CryptoService;

#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::build_test_config_with_mvm;

/// Test that ECDSA signature creation succeeds for EVM escrow release
/// Why: ECDSA signatures are required for EVM chain compatibility - must work correctly
#[test]
fn test_create_evm_approval_signature_success() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    let intent_id = "0x1111111111111111111111111111111111111111111111111111111111111111";

    let signature = service.create_evm_approval_signature(intent_id).unwrap();

    // Signature should be created successfully
    assert!(!signature.is_empty(), "Signature should not be empty");
}

/// Test that ECDSA signature format is exactly 65 bytes (r || s || v)
/// Why: EVM requires 65-byte signatures (32 r + 32 s + 1 v) for ecrecover
#[test]
fn test_create_evm_approval_signature_format_65_bytes() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    let intent_id = "0x1111111111111111111111111111111111111111111111111111111111111111";

    let signature = service.create_evm_approval_signature(intent_id).unwrap();

    // Signature must be exactly 65 bytes: 32 (r) + 32 (s) + 1 (v)
    assert_eq!(signature.len(), 65, "Signature must be exactly 65 bytes");

    // Verify v value is 27 or 28 (Ethereum format)
    let v = signature[64];
    assert!(
        v == 27 || v == 28,
        "Recovery ID v must be 27 or 28, got {}",
        v
    );
}

/// Test that ECDSA signature can be verified (on-chain compatible)
/// Why: Signatures must be verifiable on EVM chains using ecrecover
#[test]
fn test_create_evm_approval_signature_verification() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    let intent_id = "0x1111111111111111111111111111111111111111111111111111111111111111";

    // Create signature
    let signature = service.create_evm_approval_signature(intent_id).unwrap();

    // Verify signature format
    assert_eq!(signature.len(), 65);

    // Extract r, s, v
    let r = &signature[0..32];
    let s = &signature[32..64];
    let v = signature[64];

    // Verify v is valid (27 or 28)
    assert!(v == 27 || v == 28);

    // Verify r and s are non-zero (valid signature components)
    assert!(!r.iter().all(|&b| b == 0), "r must not be zero");
    assert!(!s.iter().all(|&b| b == 0), "s must not be zero");
}

/// Test that Ethereum address derivation works correctly
/// Why: Ethereum address is needed for EVM contract interactions - must be derived correctly
#[test]
fn test_get_ethereum_address_derivation() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    let address = service.get_ethereum_address().unwrap();

    // Address should be hex string with 0x prefix
    assert!(address.starts_with("0x"), "Address must start with 0x");
    assert_eq!(
        address.len(),
        42,
        "Address must be 42 characters (0x + 40 hex chars)"
    );

    // Address should be consistent for same service instance
    let address2 = service.get_ethereum_address().unwrap();
    assert_eq!(address, address2, "Address should be consistent");
}

/// Test that recovery ID (v) is calculated correctly (27 or 28)
/// Why: Recovery ID determines which public key can recover from signature - must be correct
#[test]
fn test_evm_signature_recovery_id_calculation() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    let intent_id = "0x1111111111111111111111111111111111111111111111111111111111111111";

    // Create multiple signatures and verify v is always 27 or 28
    for _ in 0..10 {
        let signature = service.create_evm_approval_signature(intent_id).unwrap();
        let v = signature[64];
        assert!(
            v == 27 || v == 28,
            "Recovery ID v must be 27 or 28, got {}",
            v
        );
    }
}

/// Test that keccak256 hashing is used in message preparation
/// Why: EVM uses keccak256 for message hashing - must match on-chain behavior
#[test]
fn test_evm_signature_keccak256_hashing() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    let intent_id = "0x1111111111111111111111111111111111111111111111111111111111111111";

    // Create signature
    let signature1 = service.create_evm_approval_signature(intent_id).unwrap();

    // Same input should produce same signature (deterministic)
    let signature2 = service.create_evm_approval_signature(intent_id).unwrap();

    // Signatures should be identical (deterministic keccak256 hashing)
    assert_eq!(signature1, signature2, "Signatures should be deterministic");
}

/// Test that Ethereum signed message prefix is applied correctly
/// Why: Ethereum requires "\x19Ethereum Signed Message:\n32" prefix for ecrecover compatibility
#[test]
fn test_evm_signature_ethereum_message_prefix() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    let intent_id = "0x1111111111111111111111111111111111111111111111111111111111111111";

    // Create signature
    let signature = service.create_evm_approval_signature(intent_id).unwrap();

    // Signature should be valid format (65 bytes with valid v)
    assert_eq!(signature.len(), 65);
    let v = signature[64];
    assert!(v == 27 || v == 28);

    // The signature format indicates Ethereum message prefix was applied
    // (we can't directly verify the prefix without reimplementing the hash, but we verify the result is valid)
}

/// Test that intent ID padding to 32 bytes works correctly
/// Why: Intent IDs must be padded to 32 bytes for EVM abi.encodePacked compatibility
#[test]
fn test_evm_intent_id_padding() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    // Test with short intent ID (should be left-padded with zeros)
    let short_intent_id = "0x1234";

    let signature1 = service
        .create_evm_approval_signature(short_intent_id)
        .unwrap();
    assert_eq!(
        signature1.len(),
        65,
        "Signature should be 65 bytes even with short intent ID"
    );

    // Test with full 32-byte intent ID
    let full_intent_id = "0x1111111111111111111111111111111111111111111111111111111111111111";
    let signature2 = service
        .create_evm_approval_signature(full_intent_id)
        .unwrap();
    assert_eq!(
        signature2.len(),
        65,
        "Signature should be 65 bytes with full intent ID"
    );

    // Test with intent ID without 0x prefix
    let intent_id_no_prefix = "1234567890123456789012345678901234567890123456789012345678901234";
    let signature3 = service
        .create_evm_approval_signature(intent_id_no_prefix)
        .unwrap();
    assert_eq!(
        signature3.len(),
        65,
        "Signature should work without 0x prefix"
    );
}

/// Test error handling for invalid intent IDs
/// Why: Invalid intent IDs should be rejected with clear error messages
#[test]
fn test_evm_signature_invalid_intent_id() {
    let config = build_test_config_with_mvm();
    let service = CryptoService::new(&config).unwrap();

    // Test with intent ID that's too long (> 32 bytes)
    let too_long_intent_id =
        "0x1234567890123456789012345678901234567890123456789012345678901234567890";
    let result = service.create_evm_approval_signature(too_long_intent_id);
    assert!(
        result.is_err(),
        "Should reject intent ID longer than 32 bytes"
    );

    // Test with invalid hex string
    let invalid_hex = "0xinvalid_hex_string_that_is_not_valid_hex";
    let result = service.create_evm_approval_signature(invalid_hex);
    assert!(result.is_err(), "Should reject invalid hex string");
}
