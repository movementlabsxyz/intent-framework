//! Aptos-specific test suite
//!
//! This module includes all Aptos-specific tests from the apt/ subdirectory.

#[path = "apt/validator_fulfillment_tests.rs"]
mod validator_fulfillment_tests;

#[path = "apt/crypto_tests.rs"]
mod crypto_tests;

#[path = "apt/cross_chain_tests.rs"]
mod cross_chain_tests;

