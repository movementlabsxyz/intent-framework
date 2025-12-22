//! Shared test helpers for solver unit tests
//!
//! This module provides constants and helper functions used by solver unit tests.

#![allow(dead_code)]

// ============================================================================
// CONSTANTS
// ============================================================================

// --------------------------------- IDs ----------------------------------

/// Dummy draft ID (UUID format)
pub const DUMMY_DRAFT_ID: &str = "11111111-1111-1111-1111-111111111111";

/// Dummy intent ID (64 hex characters, same across all chains)
pub const DUMMY_INTENT_ID: &str = "0x1111111111111111111111111111111111111111111111111111111111111111";

/// Dummy escrow ID (EVM format, 40 hex characters)
pub const DUMMY_ESCROW_ID_EVM: &str = "0x2222222222222222222222222222222222222222";

/// Dummy escrow ID (Move VM format, 64 hex characters)
pub const DUMMY_ESCROW_ID_MVM: &str = "0x2222222222222222222222222222222222222222222222222222222222222222";

// -------------------------------- USERS ---------------------------------

/// Dummy requester address on hub chain (Move VM format, 64 hex characters)
pub const DUMMY_REQUESTER_ADDR_MVM_HUB: &str = "0x3333333333333333333333333333333333333333333333333333333333333333";

/// Dummy requester address on connected chain (Move VM format, 64 hex characters)
pub const DUMMY_REQUESTER_ADDR_MVM_CON: &str = "0x4444444444444444444444444444444444444444444444444444444444444444";

/// Dummy requester address (EVM format, 40 hex characters)
pub const DUMMY_REQUESTER_ADDR_EVM: &str = "0x5555555555555555555555555555555555555555";

/// Dummy solver address on hub chain (Move VM format, 64 hex characters)
pub const DUMMY_SOLVER_ADDR_MVM_HUB: &str = "0x6666666666666666666666666666666666666666666666666666666666666666";

/// Dummy solver address on connected chain (Move VM format, 64 hex characters)
pub const DUMMY_SOLVER_ADDR_MVM_CON: &str = "0x7777777777777777777777777777777777777777777777777777777777777777";

/// Dummy solver address (EVM format, 40 hex characters)
pub const DUMMY_SOLVER_ADDR_EVM: &str = "0x8888888888888888888888888888888888888888";

// ------------------------- TOKENS AND CONTRACTS -------------------------

/// Dummy token address (EVM format, 40 hex characters)
pub const DUMMY_TOKEN_ADDR_EVM: &str = "0x9999999999999999999999999999999999999999";

/// Dummy token address on hub chain (Move VM format, 64 hex characters)
pub const DUMMY_TOKEN_ADDR_MVM_HUB: &str = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

/// Dummy token address on connected chain (Move VM format, 64 hex characters)
pub const DUMMY_TOKEN_ADDR_MVM_CON: &str = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

/// Dummy escrow contract address (EVM format, 40 hex characters)
pub const DUMMY_ESCROW_CONTRACT_ADDR_EVM: &str = "0xcccccccccccccccccccccccccccccccccccccccc";

/// Dummy intent address (Move VM format, 64 hex characters, used for intent object address on hub chain)
pub const DUMMY_INTENT_ADDR_MVM: &str = "0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd";

/// Dummy module address for hub chain (short format)
pub const DUMMY_MODULE_ADDR_HUB: &str = "0x1";

/// Dummy module address for connected chain (short format)
pub const DUMMY_MODULE_ADDR_CON: &str = "0x2";

// -------------------------------- OTHER ---------------------------------

/// Dummy transaction hash (64 hex characters)
pub const DUMMY_TX_HASH: &str = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";

/// Dummy expiry timestamp (far future timestamp for tests)
pub const DUMMY_EXPIRY: u64 = 9999999999;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a base token pair with default test values.
/// This can be customized using Rust's struct update syntax:
/// ```
/// let pair = TokenPair {
///     desired_token: "0xccc...".to_string(),
///     ..create_base_token_pair()
/// };
/// ```
pub fn create_base_token_pair() -> solver::acceptance::TokenPair {
    solver::acceptance::TokenPair {
        offered_chain_id: 1,
        offered_token: DUMMY_TOKEN_ADDR_MVM_HUB.to_string(),
        desired_chain_id: 2,
        desired_token: DUMMY_TOKEN_ADDR_MVM_CON.to_string(),
    }
}
