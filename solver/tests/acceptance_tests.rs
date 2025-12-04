//! Unit tests for draft intent acceptance logic
//!
//! These tests verify that the solver correctly evaluates draft intents
//! based on token types and amounts.

use solver::acceptance::{AcceptanceConfig, AcceptanceResult, DraftintentData, should_accept_draft};
use std::collections::HashMap;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a base TokenPair with default test values
/// This can be customized using Rust's struct update syntax:
/// ```
/// let pair = TokenPair {
///     desired_token: "0xccc...".to_string(),
///     ..create_base_token_pair()
/// };
/// ```
fn create_base_token_pair() -> solver::acceptance::TokenPair {
    solver::acceptance::TokenPair {
        offered_chain_id: 1,
        offered_token: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        desired_chain_id: 2,
        desired_token: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(),
    }
}

/// Create a base acceptance config with default test values
fn test_config() -> AcceptanceConfig {
    use solver::acceptance::TokenPair;
    
    let mut token_pairs = HashMap::new();
    
    // Token A -> Token B (1:1 rate)
    token_pairs.insert(
        TokenPair {
            ..create_base_token_pair()
        },
        1.0,  // 1:1 exchange rate
    );
    
    // Token A -> Token C (chain 2) (0.5 rate: 1 Token C = 0.5 Token A, cross-chain)
    token_pairs.insert(
        TokenPair {
            desired_token: "0xcccccccccccccccccccccccccccccccccccccccc".to_string(),
            ..create_base_token_pair()
        },
        0.5,  // 0.5 offered per 1 desired
    );
    
    AcceptanceConfig {
        token_pairs,
    }
}

/// Create a base draft intent data with default test values
/// This can be customized using Rust's struct update syntax:
/// ```
/// let draft = create_base_draft_data();
/// let custom_draft = DraftintentData {
///     offered_amount: 500000,
///     desired_amount: 1000000,
///     ..draft
/// };
/// ```
fn create_base_draft_data() -> DraftintentData {
    DraftintentData {
        offered_token: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        offered_amount: 1000000,
        offered_chain_id: 1,
        desired_token: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(),
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
    let draft = DraftintentData {
        ..create_base_draft_data()  // 1:1 rate, offered=1000000, desired=1000000
    };
    assert!(matches!(should_accept_draft(&draft, &config), AcceptanceResult::Accept));
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
        ..create_base_draft_data()
    };
    assert!(matches!(should_accept_draft(&draft, &config), AcceptanceResult::Reject(_)));
}

/// Test that token pair swaps with non-1:1 exchange rates are accepted when offered meets configured rate
/// What is tested: Exchange rate calculation for configured token pairs (0.5 rate in this test)
/// Why: Solver should accept swaps when offered amount meets the configured exchange rate for the token pair
#[test]
fn test_token_pair_with_exchange_rate_accept() {
    let config = test_config();
    let draft = DraftintentData {
        desired_token: "0xcccccccccccccccccccccccccccccccccccccccc".to_string(),  // Token C
        desired_amount: 2000000,  // 2.0 Token C (at 0.5 rate, requires 1.0 offered)
        ..create_base_draft_data()  // offered_amount: 1000000 (1.0) meets the requirement (2.0 * 0.5 = 1.0)
    };
    assert!(matches!(should_accept_draft(&draft, &config), AcceptanceResult::Accept));
}

/// Test that unsupported token pairs are rejected
/// What is tested: Token pair validation
/// Why: Solver should only accept configured token pairs
#[test]
fn test_unsupported_token_pair_rejected() {
    let config = test_config();
    let draft = DraftintentData {
        offered_token: "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc".to_string(),  // Token not in any configured pair
        ..create_base_draft_data()  // offered_amount: 1000000, desired_amount: 1000000, but pair is not configured
    };
    assert!(matches!(should_accept_draft(&draft, &config), AcceptanceResult::Reject(_)));
}

