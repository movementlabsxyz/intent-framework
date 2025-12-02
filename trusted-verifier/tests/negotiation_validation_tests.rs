//! Unit tests for negotiation signature validation
//!
//! These tests verify signature format validation logic used in signature submission endpoints.

use trusted_verifier::api::validate_signature_format;

#[path = "mod.rs"]
mod test_helpers;

// ============================================================================
// SIGNATURE FORMAT VALIDATION TESTS
// ============================================================================

/// Test that valid Ed25519 signature format passes validation
/// What is tested: 128 hex characters (64 bytes) signature format
/// Why: Ed25519 signatures must be exactly 64 bytes
#[test]
fn test_validate_signature_format_valid() {
    // Valid signature: 128 hex chars
    let valid_sig = "a".repeat(128);
    assert!(validate_signature_format(&valid_sig).is_ok());
    
    // Valid signature with 0x prefix
    let valid_sig_with_prefix = "0x".to_string() + &"b".repeat(128);
    assert!(validate_signature_format(&valid_sig_with_prefix).is_ok());
}

/// Test that signature with wrong length fails validation
/// What is tested: Length validation (must be 128 hex chars)
/// Why: Ed25519 signatures must be exactly 64 bytes
#[test]
fn test_validate_signature_format_wrong_length() {
    // Too short
    let short_sig = "a".repeat(64);
    let result = validate_signature_format(&short_sig);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("expected 128 hex characters"));
    
    // Too long
    let long_sig = "a".repeat(256);
    let result = validate_signature_format(&long_sig);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("expected 128 hex characters"));
}

/// Test that signature with invalid hex characters fails validation
/// What is tested: Hex character validation
/// Why: Signatures must be valid hexadecimal
#[test]
fn test_validate_signature_format_invalid_hex() {
    // Contains non-hex characters
    let invalid_sig = "g".repeat(128);
    let result = validate_signature_format(&invalid_sig);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("not valid hex"));
    
    // Contains uppercase non-hex (G-Z)
    let invalid_sig2 = "G".repeat(128);
    let result = validate_signature_format(&invalid_sig2);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("not valid hex"));
}

/// Test that signature with valid hex but wrong case still passes
/// What is tested: Case insensitivity (hex is case-insensitive)
/// Why: Hex can be uppercase or lowercase
#[test]
fn test_validate_signature_format_case_insensitive() {
    // Uppercase hex
    let uppercase_sig = "ABCDEF0123456789".repeat(8); // 128 chars
    assert!(validate_signature_format(&uppercase_sig).is_ok());
    
    // Mixed case hex
    let mixed_sig = "aBcDeF0123456789".repeat(8); // 128 chars
    assert!(validate_signature_format(&mixed_sig).is_ok());
}

/// Test that empty signature fails validation
/// What is tested: Empty string handling
/// Why: Empty signatures are invalid
#[test]
fn test_validate_signature_format_empty() {
    let result = validate_signature_format("");
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("expected 128 hex characters"));
}

/// Test that signature with only 0x prefix fails validation
/// What is tested: 0x prefix handling when signature is empty
/// Why: 0x prefix alone is not a valid signature
#[test]
fn test_validate_signature_format_only_prefix() {
    let result = validate_signature_format("0x");
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("expected 128 hex characters"));
}

