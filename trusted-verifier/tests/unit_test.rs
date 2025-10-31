//! Unit tests entry point
//!
//! This file is discovered by Cargo and loads all unit tests
//! from the `tests/` directory.

mod config_tests;
mod cross_chain_tests;
mod crypto_tests;
mod monitor_tests;

// Load and re-export shared test helpers from mod.rs
#[path = "mod.rs"]
mod test_helpers;
pub use test_helpers::build_test_config;

