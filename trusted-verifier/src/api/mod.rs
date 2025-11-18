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
mod inflow_mvm;
mod inflow_evm;
mod outflow_mvm;
mod outflow_evm;

// Re-export generic structures and ApiServer for convenience
pub use generic::{ApiResponse, ApiServer};