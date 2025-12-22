//! Unit tests for EVM cross-chain matching logic
//!
//! These tests verify that EVM escrow events can be matched to hub intent events
//! across different chains using intent_id, and test intent ID format conversions.

use trusted_verifier::monitor::{EscrowEvent, IntentEvent};
#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::{create_default_escrow_event_evm, create_default_intent_evm, DUMMY_EXPIRY, DUMMY_INTENT_ID};

/// Test that EVM escrow can be matched to hub intent by intent_id
/// Why: Verify cross-chain matching logic correctly links EVM escrow to hub intent
#[test]
fn test_evm_escrow_cross_chain_matching() {
    // Step 1: Create hub intent
    let hub_intent = create_default_intent_evm();

    // Step 2: Create EVM escrow with matching intent_id
    // Use the realistic EVM escrow helper which has empty desired_metadata
    let evm_escrow = EscrowEvent {
        requester_addr: hub_intent.requester_addr.clone(), // Match hub intent requester (MVM format) instead of default EVM address
        ..create_default_escrow_event_evm()
    };

    // Step 3: Verify matching logic (simulating the matching in validate_intent_fulfillment)
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

    // Verify EVM escrow has empty desired_metadata (realistic behavior)
    assert_eq!(
        evm_escrow.desired_metadata, "{}",
        "EVM escrow desired_metadata should be empty"
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
    let mvmt_intent_id_full = DUMMY_INTENT_ID;
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
    // Step 1: Create hub intent
    let hub_intent = IntentEvent {
        expiry_time: DUMMY_EXPIRY,
        ..create_default_intent_evm()
    };

    // Step 2: Create EVM escrow on connected chain with matching intent_id
    // Use the realistic EVM escrow helper which has empty desired_metadata
    // (because the EVM IntentEscrow contract doesn't store this field)
    let evm_escrow = EscrowEvent {
        requester_addr: hub_intent.requester_addr.clone(), // Match hub intent requester (MVM format) instead of default EVM address
        expiry_time: DUMMY_EXPIRY, // Matches hub intent expiry (default sets 0)
        ..create_default_escrow_event_evm()
    };

    // Step 3: Verify cross-chain matching (simulating validate_intent_fulfillment logic)
    let intent_cache = vec![hub_intent.clone()];
    let matching_intent = intent_cache
        .iter()
        .find(|intent| intent.intent_id == evm_escrow.intent_id);

    assert!(
        matching_intent.is_some(),
        "Should find matching Move VM hub intent for EVM escrow"
    );
    let matched = matching_intent.unwrap();

    // Verify all matching criteria (as per validate_intent_fulfillment validation)
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
        matched.requester_addr, evm_escrow.requester_addr,
        "Request-intent requester should match escrow issuer"
    );

    // Verify EVM-specific behavior: escrow_id equals intent_id
    assert_eq!(
        evm_escrow.escrow_id, evm_escrow.intent_id,
        "For EVM, escrow_id should equal intent_id"
    );

    // Verify escrow desired_metadata is empty (escrows only store offered tokens, not desired)
    // For inflow escrows, desired_metadata is only on the hub chain intent.
    assert_eq!(
        evm_escrow.desired_metadata, "{}",
        "Inflow escrow desired_metadata should be empty (only stores offered tokens)"
    );

    // Verify desired_amount is 0 for inflow escrows (escrow only holds offered funds)
    assert_eq!(
        evm_escrow.desired_amount, 0,
        "Inflow escrow desired_amount must be 0"
    );

    // Note: Inflow escrow desired_metadata is NOT validated against intent.desired_metadata
    // because escrows only store what's offered/locked, not what's desired.
    // The intent's desired_metadata indicates what requester wants on hub chain.
    assert_ne!(
        evm_escrow.desired_metadata, matched.desired_metadata,
        "Escrow and intent desired_metadata should NOT match (escrow doesn't store it)"
    );
}
