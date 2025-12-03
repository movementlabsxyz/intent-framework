//! Cryptographic operations for solver
//!
//! This module provides hash calculation and signing functionality.

pub mod hash;
pub mod signing;

// Re-export for convenience
pub use hash::get_intent_hash;
pub use signing::{get_private_key_from_profile, sign_intent_hash};

