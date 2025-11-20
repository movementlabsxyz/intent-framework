//! Move VM-specific test suite
//!
//! This module includes all Move VM-specific tests from the mvm/ subdirectory.

#[path = "mvm/validator_fulfillment_tests.rs"]
mod validator_fulfillment_tests;

#[path = "mvm/crypto_tests.rs"]
mod crypto_tests;

#[path = "mvm/cross_chain_tests.rs"]
mod cross_chain_tests;
