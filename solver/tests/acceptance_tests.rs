//! Unit tests for draft intent acceptance logic
//!
//! These tests verify that the solver correctly evaluates draft intents
//! based on token types and amounts.

use solver::acceptance::{AcceptanceConfig, AcceptanceResult, DraftintentData, evaluate_draft_acceptance};
use std::collections::HashMap;

#[path = "helpers.rs"]
mod test_helpers;
use test_helpers::{
    create_default_token_pair, DUMMY_INTENT_ID, DUMMY_TOKEN_ADDR_MVM_HUB, DUMMY_TOKEN_ADDR_MVM_CON,
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a default acceptance config with test values
fn test_config() -> AcceptanceConfig {
    use solver::acceptance::TokenPair;
    
    let mut token_pairs = HashMap::new();
    
    // Token A -> Token B (1:1 rate)
    token_pairs.insert(
        create_default_token_pair(),
        1.0,  // 1:1 exchange rate
    );
    
    // Token A -> Token C (chain 2) (0.5 rate: 1 Token C = 0.5 Token A, cross-chain)
    token_pairs.insert(
        TokenPair {
            desired_token: "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff".to_string(), // Token C on chain 2 (different from Token B)
            ..create_default_token_pair()
        },
        0.5,  // 0.5 offered per 1 desired
    );
    
    AcceptanceConfig {
        token_pairs,
    }
}

/// Create a default draft intent data with test values
/// This can be customized using Rust's struct update syntax:
/// ```
/// let draft = create_default_draft_data();
/// let custom_draft = DraftintentData {
///     offered_amount: 500000,
///     desired_amount: 1000000,
///     ..draft
/// };
/// ```
fn create_default_draft_data() -> DraftintentData {
    DraftintentData {
        intent_id: DUMMY_INTENT_ID.to_string(),
        offered_token: DUMMY_TOKEN_ADDR_MVM_HUB.to_string(),
        offered_amount: 1000000,
        offered_chain_id: 1,
        desired_token: DUMMY_TOKEN_ADDR_MVM_CON.to_string(),
        desired_amount: 1000000,
        desired_chain_id: 2,
    }
}

/// Test that token pair swaps are accepted when offered >= required amount at configured exchange rate
/// What is tested: Token pair validation and exchange rate calculation (1:1 rate in this test)
/// Why: Solver should accept swaps when offered amount meets the configured exchange rate for the token pair
#[test]
fn test_token_pair_accept() {
    let config = test_config();
    let draft = create_default_draft_data(); // 1:1 rate, offered=1000000, desired=1000000
    assert!(matches!(evaluate_draft_acceptance(&draft, &config), AcceptanceResult::Accept));
}

/// Test that token pair swaps are rejected when offered < required amount at configured exchange rate
/// What is tested: Exchange rate validation (1:1 rate in this test)
/// Why: Solver should reject swaps when offered amount doesn't meet the configured exchange rate for the token pair
#[test]
fn test_token_pair_reject_unfavorable() {
    let config = test_config();
    let draft = DraftintentData {
        offered_amount: 500000,  // 0.5 is less than the required amount 1.0 at configured 1:1 exchange rate
        desired_amount: 1000000,  // 1.0 requires 1.0 offered at configured 1:1 exchange rate
        ..create_default_draft_data()
    };
    assert!(matches!(evaluate_draft_acceptance(&draft, &config), AcceptanceResult::Reject(_)));
}

/// Test that token pair swaps with non-1:1 exchange rates are accepted when offered meets configured rate
/// What is tested: Exchange rate calculation for configured token pairs (0.5 rate in this test)
/// Why: Solver should accept swaps when offered amount meets the configured exchange rate for the token pair
#[test]
fn test_token_pair_with_exchange_rate_accept() {
    let config = test_config();
    let draft = DraftintentData {
        desired_token: "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff".to_string(), // Token C on chain 2 (different from Token B)
        desired_amount: 2000000,  // 2.0 Token C (at 0.5 rate, requires 1.0 offered)
        ..create_default_draft_data()  // offered_amount: 1000000 (1.0) meets the requirement (2.0 * 0.5 = 1.0)
    };
    assert!(matches!(evaluate_draft_acceptance(&draft, &config), AcceptanceResult::Accept));
}

/// Test that unsupported token pairs are rejected
/// What is tested: Token pair validation
/// Why: Solver should only accept configured token pairs
#[test]
fn test_unsupported_token_pair_rejected() {
    let config = test_config();
    let draft = DraftintentData {
        offered_token: "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff".to_string(), // Unsupported token (not in any configured pair)
        ..create_default_draft_data()  // offered_amount: 1000000, desired_amount: 1000000, but pair is not configured
    };
    assert!(matches!(evaluate_draft_acceptance(&draft, &config), AcceptanceResult::Reject(_)));
}

