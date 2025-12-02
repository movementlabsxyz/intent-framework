//! REST API Server Module
//!
//! This module provides a REST API server for the trusted verifier service,
//! exposing endpoints for monitoring events, validating fulfillments, and
//! retrieving approval signatures. It handles HTTP requests and provides
//! JSON responses for external system integration.
//!
//! ## Security Requirements
//!
//! **CRITICAL**: All API endpoints must validate that escrow intents are **non-revocable**
//! (`revocable = false`) before providing any approval signatures.

// Generic shared code
mod generic;

// Flow-specific modules (chain-agnostic)
mod inflow_generic;
mod outflow_generic;

// Flow + chain specific modules
mod inflow_evm;
mod inflow_mvm;
mod outflow_evm;
mod outflow_mvm;

// Negotiation routing module
mod negotiation;

// Re-export ApiServer for convenience
pub use generic::ApiServer;
// Re-export ApiResponse for testing
#[allow(unused_imports)]
pub use generic::ApiResponse;
// Re-export negotiation validation functions for testing
#[allow(unused_imports)]
pub use negotiation::validate_signature_format;
