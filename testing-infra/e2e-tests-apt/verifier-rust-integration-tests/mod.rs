//! Integration tests module
//!
//! This module contains integration tests that require external services
//! (such as running Aptos chains).
//!
//! These tests are located in testing-infra/e2e-tests-apt/verifier-rust-integration-tests/
//! and require Docker chains to be running.

pub mod connectivity_test;
pub mod deployment_test;
pub mod event_polling_test;

