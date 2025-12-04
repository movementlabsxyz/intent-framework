//! Storage Module
//!
//! This module provides storage abstractions for the trusted verifier service,
//! including draft intent storage for negotiation routing.

pub mod draftintents;

// Re-export for convenience
pub use draftintents::{DraftintentStatus, DraftintentStore};

