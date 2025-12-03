//! Solver service modules
//!
//! This module contains service implementations for the solver,
//! including the signing service loop and intent tracking.

pub mod signing;
pub mod tracker;

// Re-export for convenience
pub use signing::{parse_draft_data, SigningService};
pub use tracker::{IntentState, IntentTracker, TrackedIntent};

