//! Unit tests for EVM cross-chain matching logic
//!
//! These tests verify that EVM escrow events can be matched to hub intent events
//! across different chains using intent_id, and test intent ID format conversions.

use trusted_verifier::monitor::{EscrowEvent, RequestIntentEvent};
#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::{create_base_escrow_event, create_base_request_intent_evm};

/// Test that EVM escrow can be matched to hub intent by intent_id
/// Why: Verify cross-chain matching logic correctly links EVM escrow to hub intent
#[test]
fn test_evm_escrow_cross_chain_matching() {
    // Step 1: Create hub intent
    let hub_intent = create_base_request_intent_evm();

    // Step 2: Create EVM escrow with matching intent_id
    // For EVM, the intent_id from Move VM is used directly (after conversion to uint256 on-chain)
    // In the verifier, we match by string intent_id
    // For EVM, escrow_id must equal intent_id
    let evm_escrow = EscrowEvent {
        escrow_id: hub_intent.intent_id.clone(), // For EVM, escrow_id = intent_id
        chain_type: trusted_verifier::ChainType::Evm,
        ..create_base_escrow_event()
    };

    // Step 3: Verify matching logic (simulating the matching in validate_request_intent_fulfillment)
    // The matching logic finds intent by intent_id: cache.iter().find(|intent| intent.intent_id == escrow_event.intent_id)
    let intent_cache = vec![hub_intent.clone()];
    let matching_intent = intent_cache
        .iter()
        .find(|intent| intent.intent_id == evm_escrow.intent_id);

    assert!(
        matching_intent.is_some(),
        "EVM escrow should match hub intent by intent_id"
    );
    let matched_intent = matching_intent.unwrap();
    assert_eq!(
        matched_intent.intent_id, evm_escrow.intent_id,
        "Intent IDs should match"
    );
    assert_eq!(
        matched_intent.offered_amount, evm_escrow.offered_amount,
        "Escrow offered amount should match hub intent offered_amount"
    );

    // Verify EVM-specific behavior: escrow_id equals intent_id for EVM
    assert_eq!(
        evm_escrow.escrow_id, evm_escrow.intent_id,
        "For EVM, escrow_id should equal intent_id"
    );
}

/// Test intent ID format conversion from Move VM hex to EVM format
/// Why: Verify that Move VM hex intent IDs can be properly converted for EVM use
#[test]
fn test_intent_id_conversion_to_evm_format() {
    // Move VM intent IDs are hex strings (e.g., "0xabc123")
    // EVM intent IDs are uint256 values (32 bytes)
    // The conversion pads hex strings to 32 bytes

    // Test 1: Short hex string (should be padded)
    let mvmt_intent_id_short = "0x1234";
    let intent_id_hex = mvmt_intent_id_short
        .strip_prefix("0x")
        .unwrap_or(mvmt_intent_id_short);
    let intent_id_bytes = hex::decode(intent_id_hex).unwrap();

    // Pad to 32 bytes
    let mut intent_id_padded = [0u8; 32];
    if intent_id_bytes.len() <= 32 {
        intent_id_padded[32 - intent_id_bytes.len()..].copy_from_slice(&intent_id_bytes);
    }

    assert_eq!(
        intent_id_padded.len(),
        32,
        "Intent ID should be padded to 32 bytes"
    );
    assert_eq!(
        intent_id_padded[30], 0x12,
        "First byte should be at correct position"
    );
    assert_eq!(
        intent_id_padded[31], 0x34,
        "Second byte should be at correct position"
    );

    // Test 2: Full 32-byte hex string (no padding needed)
    let mvmt_intent_id_full = "0x1111111111111111111111111111111111111111111111111111111111111111";
    let intent_id_hex_full = mvmt_intent_id_full
        .strip_prefix("0x")
        .unwrap_or(mvmt_intent_id_full);
    let intent_id_bytes_full = hex::decode(intent_id_hex_full).unwrap();

    assert_eq!(
        intent_id_bytes_full.len(),
        32,
        "Full intent ID should be 32 bytes"
    );

    // Test 3: Empty hex string (should pad to all zeros)
    let mvmt_intent_id_empty = "0x";
    let intent_id_hex_empty = mvmt_intent_id_empty
        .strip_prefix("0x")
        .unwrap_or(mvmt_intent_id_empty);
    let intent_id_bytes_empty = if intent_id_hex_empty.is_empty() {
        Vec::new()
    } else {
        hex::decode(intent_id_hex_empty).unwrap()
    };

    let mut intent_id_padded_empty = [0u8; 32];
    if intent_id_bytes_empty.len() <= 32 {
        intent_id_padded_empty[32 - intent_id_bytes_empty.len()..]
            .copy_from_slice(&intent_id_bytes_empty);
    }

    assert_eq!(
        intent_id_padded_empty, [0u8; 32],
        "Empty intent ID should pad to all zeros"
    );
}

/// Test EVM escrow matching with Move VM hub intent in cross-chain scenario
/// Why: Verify complete cross-chain matching workflow from Move VM hub to EVM escrow
#[test]
fn test_evm_escrow_matching_with_hub_intent() {
    // Step 1: Create  hub intent
    let hub_intent = RequestIntentEvent {
        expiry_time: 2000000,
        ..create_base_request_intent_evm()
    };

    // Step 2: Create EVM escrow on connected chain with matching intent_id
    // For EVM, escrow_id must equal intent_id
    let evm_escrow = EscrowEvent {
        escrow_id: hub_intent.intent_id.clone(), // EVM: escrow_id = intent_id
        chain_type: trusted_verifier::ChainType::Evm,
        expiry_time: 2000000, // Matches hub intent expiry
        ..create_base_escrow_event()
    };

    // Step 3: Verify cross-chain matching (simulating validate_request_intent_fulfillment logic)
    let intent_cache = vec![hub_intent.clone()];
    let matching_intent = intent_cache
        .iter()
        .find(|intent| intent.intent_id == evm_escrow.intent_id);

    assert!(
        matching_intent.is_some(),
        "Should find matching Move VM hub intent for EVM escrow"
    );
    let matched = matching_intent.unwrap();

    // Verify all matching criteria (as per validate_request_intent_fulfillment validation)
    assert_eq!(
        matched.intent_id, evm_escrow.intent_id,
        "Intent IDs must match"
    );
    assert_eq!(
        matched.offered_amount, evm_escrow.offered_amount,
        "Escrow offered amount should match hub intent offered_amount"
    );
    assert_eq!(
        matched.expiry_time, evm_escrow.expiry_time,
        "Expiry times should match"
    );
    assert_eq!(
        matched.requester, evm_escrow.issuer,
        "Request intent requester should match escrow issuer"
    );

    // Verify EVM-specific behavior: escrow_id equals intent_id
    assert_eq!(
        evm_escrow.escrow_id, evm_escrow.intent_id,
        "For EVM, escrow_id should equal intent_id"
    );

    // Verify validation criteria that would be checked in validate_request_intent_fulfillment
    // Escrow desired_amount is always 0 (escrow only holds offered funds)
    assert_eq!(
        evm_escrow.desired_amount, 0,
        "Escrow desired amount must be 0"
    );
    assert_eq!(
        evm_escrow.desired_metadata, matched.desired_metadata,
        "Metadata should match"
    );
}
