//! Simple test for solver signature generation
//!
//! This test verifies that the core Ed25519 signature generation works correctly
//! without requiring Aptos CLI or config files.

use ed25519_dalek::{Signer, SigningKey};
use rand::Rng;

/// Test that we can generate a valid Ed25519 signature
/// This verifies the core signing logic used by sign_intent binary
#[test]
fn test_ed25519_signature_generation() {
    // Generate a random private key (32 bytes)
    let mut rng = rand::thread_rng();
    let mut private_key_bytes = [0u8; 32];
    rng.fill(&mut private_key_bytes);

    // Create signing key
    let signing_key = SigningKey::from_bytes(&private_key_bytes);
    let verifying_key = signing_key.verifying_key();

    // Create a test message hash (simulating BCS-encoded IntentToSign)
    let message_hash = b"test message hash for intent signing";

    // Sign the message
    let signature = signing_key.sign(message_hash);
    let signature_bytes = signature.to_bytes();

    // Verify signature is 64 bytes (Ed25519 signature length)
    assert_eq!(
        signature_bytes.len(),
        64,
        "Ed25519 signature must be 64 bytes"
    );

    // Verify the signature
    verifying_key
        .verify_strict(message_hash, &signature)
        .expect("Signature should be valid");

    // Test hex encoding (as used in the binary)
    let signature_hex = format!("0x{}", hex::encode(signature_bytes));
    assert!(
        signature_hex.starts_with("0x"),
        "Hex signature should start with 0x"
    );
    assert_eq!(
        signature_hex.len(),
        130,
        "Hex signature should be 130 chars (0x + 128 hex chars)"
    );
}

/// Test that signature verification fails with wrong message
#[test]
fn test_signature_verification_fails_wrong_message() {
    let mut rng = rand::thread_rng();
    let mut private_key_bytes = [0u8; 32];
    rng.fill(&mut private_key_bytes);

    let signing_key = SigningKey::from_bytes(&private_key_bytes);
    let verifying_key = signing_key.verifying_key();

    let message1 = b"original message";
    let message2 = b"different message";

    let signature = signing_key.sign(message1);

    // Should verify with correct message
    verifying_key
        .verify_strict(message1, &signature)
        .expect("Signature should be valid for correct message");

    // Should fail with wrong message
    let result = verifying_key.verify_strict(message2, &signature);
    assert!(
        result.is_err(),
        "Signature should fail verification with wrong message"
    );
}

/// Test base64 private key parsing (as used in get_private_key_from_profile)
#[test]
fn test_parse_private_key_base64() {
    use base64::{engine::general_purpose, Engine as _};

    // Generate a test private key
    let mut rng = rand::thread_rng();
    let mut private_key_bytes = [0u8; 32];
    rng.fill(&mut private_key_bytes);

    // Encode to base64
    let private_key_b64 = general_purpose::STANDARD.encode(private_key_bytes);

    // Decode back
    let decoded_bytes = general_purpose::STANDARD
        .decode(&private_key_b64)
        .expect("Should decode base64");

    assert_eq!(decoded_bytes.len(), 32, "Decoded key should be 32 bytes");
    assert_eq!(
        decoded_bytes, private_key_bytes,
        "Decoded key should match original"
    );
}

/// Test address normalization (strip 0x prefix) as used in get_intent_hash
/// This verifies that solver addresses are correctly normalized for REST API queries
#[test]
fn test_solver_address_normalization() {
    // Test case 1: Address with 0x prefix should have it removed
    let solver_with_prefix = "0x1234567890abcdef";
    let normalized = solver_with_prefix
        .strip_prefix("0x")
        .unwrap_or(solver_with_prefix);
    assert_eq!(normalized, "1234567890abcdef", "Should remove 0x prefix");

    // Test case 2: Address without 0x prefix should remain unchanged
    let solver_without_prefix = "1234567890abcdef";
    let normalized2 = solver_without_prefix
        .strip_prefix("0x")
        .unwrap_or(solver_without_prefix);
    assert_eq!(
        normalized2, "1234567890abcdef",
        "Should remain unchanged when no prefix"
    );

    // Test case 3: Empty string edge case
    let solver_empty = "";
    let normalized3 = solver_empty.strip_prefix("0x").unwrap_or(solver_empty);
    assert_eq!(normalized3, "", "Empty string should remain empty");

    // Test case 4: Address with only 0x (edge case)
    let solver_only_prefix = "0x";
    let normalized4 = solver_only_prefix
        .strip_prefix("0x")
        .unwrap_or(solver_only_prefix);
    assert_eq!(normalized4, "", "Should remove prefix leaving empty string");

    // Test case 5: Real Aptos address format (64 hex chars)
    let real_address = "0x7a4086988c99f3961fc8505fc4de995706fc5d3a6f5a3c55f95e49cae4b5bf45";
    let normalized5 = real_address.strip_prefix("0x").unwrap_or(real_address);
    assert_eq!(
        normalized5, "7a4086988c99f3961fc8505fc4de995706fc5d3a6f5a3c55f95e49cae4b5bf45",
        "Real address should be normalized correctly"
    );

    // Test case 6: Address without prefix (64 hex chars)
    let real_address_no_prefix = "7a4086988c99f3961fc8505fc4de995706fc5d3a6f5a3c55f95e49cae4b5bf45";
    let normalized6 = real_address_no_prefix
        .strip_prefix("0x")
        .unwrap_or(real_address_no_prefix);
    assert_eq!(
        normalized6, real_address_no_prefix,
        "Address without prefix should remain unchanged"
    );
}
