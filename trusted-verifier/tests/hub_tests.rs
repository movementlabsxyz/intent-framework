//! Hub chain-specific test suite
//!
//! This module includes all hub chain-specific tests from the hub/ subdirectory.

#[path = "hub/validator_tests.rs"]
mod validator_tests;

#[path = "hub/event_parsing_tests.rs"]
mod event_parsing_tests;
