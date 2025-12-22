//! Shared test helpers for solver unit tests
//!
//! This module provides constants and helper functions used by solver unit tests.

#![allow(dead_code)]

// ============================================================================
// CONSTANTS
// ============================================================================

/// Dummy module address for hub chain (short format)
pub const DUMMY_MODULE_ADDR_HUB: &str = "0x1";

/// Dummy module address for connected chain (short format)
pub const DUMMY_MODULE_ADDR_CONNECTED: &str = "0x2";

/// Dummy offered token/metadata address (Move VM format, 64 hex characters)
pub const DUMMY_OFFERED_TOKEN_MVM: &str = "0x1111111111111111111111111111111111111111111111111111111111111111";

/// Dummy desired token/metadata address (Move VM format, 64 hex characters)
pub const DUMMY_DESIRED_TOKEN_MVM: &str = "0x2222222222222222222222222222222222222222222222222222222222222222";

/// Dummy solver address (EVM format, 40 hex characters)
pub const DUMMY_SOLVER_ADDR_EVM: &str = "0x3333333333333333333333333333333333333333";

/// Dummy token address (EVM format, 40 hex characters)
pub const DUMMY_TOKEN_ADDR_EVM: &str = "0x4444444444444444444444444444444444444444";
