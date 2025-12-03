//! Solver library for intent framework
//!
//! Provides signing, acceptance logic, and verifier communication.

pub mod acceptance;
pub mod crypto;

// Re-export public types for convenience
pub use acceptance::{AcceptanceConfig, AcceptanceResult, DraftIntentData};
pub use crypto::{get_intent_hash, get_private_key_from_profile, sign_intent_hash};

