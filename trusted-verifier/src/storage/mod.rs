//! Storage Module
//!
//! This module provides storage abstractions for the trusted verifier service,
//! including draft intent storage for negotiation routing.

pub mod draft_intents;

// Re-export for convenience
pub use draft_intents::{DraftIntentStatus, DraftIntentStore};

