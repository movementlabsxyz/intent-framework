//! EVM-specific test suite
//!
//! This module includes all EVM-specific tests from the evm/ subdirectory.

#[path = "evm/validator_fulfillment_tests.rs"]
mod validator_fulfillment_tests;

#[path = "evm/validator_tests.rs"]
mod validator_tests;

#[path = "evm/config_tests.rs"]
mod config_tests;

#[path = "evm/crypto_tests.rs"]
mod crypto_tests;

#[path = "evm/monitor_tests.rs"]
mod monitor_tests;

#[path = "evm/cross_chain_tests.rs"]
mod cross_chain_tests;
