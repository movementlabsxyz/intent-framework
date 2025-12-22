//! Shared test helpers for solver unit tests
//!
//! This module provides constants and helper functions used by solver unit tests.

#![allow(dead_code)]

// ============================================================================
// CONSTANTS
// ============================================================================

/// Dummy draft ID (UUID format)
pub const DUMMY_DRAFT_ID: &str = "11111111-1111-1111-1111-111111111111";

/// Dummy intent ID (Move VM format, 64 hex characters)
pub const DUMMY_INTENT_ID: &str = "0x1111111111111111111111111111111111111111111111111111111111111111";

/// Dummy requester address (EVM format, 40 hex characters)
pub const DUMMY_REQUESTER_ADDR_EVM: &str = "0x2222222222222222222222222222222222222222";

/// Dummy solver address (EVM format, 40 hex characters)
pub const DUMMY_SOLVER_ADDR_EVM: &str = "0x3333333333333333333333333333333333333333";

/// Dummy token address on hub chain (Move VM format, 64 hex characters)
pub const DUMMY_TOKEN_ADDR_MVM_HUB: &str = "0x4444444444444444444444444444444444444444444444444444444444444444";

/// Dummy token address on connected chain (Move VM format, 64 hex characters)
pub const DUMMY_TOKEN_ADDR_MVM_CON: &str = "0x5555555555555555555555555555555555555555555555555555555555555555";

/// Dummy token address (EVM format, 40 hex characters)
pub const DUMMY_TOKEN_ADDR_EVM: &str = "0x6666666666666666666666666666666666666666";

/// Dummy escrow ID (EVM format, 40 hex characters)
pub const DUMMY_ESCROW_ID_EVM: &str = "0x7777777777777777777777777777777777777777";

/// Dummy transaction hash (64 hex characters)
pub const DUMMY_TX_HASH: &str = "0x8888888888888888888888888888888888888888888888888888888888888888";

/// Dummy module address for hub chain (short format)
pub const DUMMY_MODULE_ADDR_HUB: &str = "0x1";

/// Dummy module address for connected chain (short format)
pub const DUMMY_MODULE_ADDR_CON: &str = "0x2";

/// Dummy expiry timestamp (far future timestamp for tests)
pub const DUMMY_EXPIRY: u64 = 9999999999;
