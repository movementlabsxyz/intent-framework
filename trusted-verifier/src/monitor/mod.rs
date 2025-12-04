//! Event Monitoring Module
//!
//! This module handles monitoring blockchain events from both hub and connected chains.
//! It listens for intent creation events on the hub chain and escrow deposit events
//! on the connected chain, providing real-time event processing and caching.
//!
//! ## Security Requirements
//!
//! **CRITICAL**: The monitor must validate that escrow intents are **non-revocable**
//! (`revocable = false`) before allowing any cross-chain actions to proceed.

// Generic shared code
mod generic;

// Flow-specific modules (chain-agnostic)
mod inflow_generic;
mod outflow_generic;

// Flow + chain specific modules
mod hub_mvm;
mod inflow_evm;
mod inflow_mvm;
mod outflow_evm;

// Re-export public types and functions
pub use generic::{
    ChainType, EscrowApproval, EscrowEvent, EventMonitor, FulfillmentEvent, IntentEvent,
};

// Re-export test utilities (used in integration tests)
#[doc(hidden)]
#[allow(unused_imports)] // Only used in tests, not in library code
pub use generic::{normalize_intent_id, normalize_intent_id_to_64_chars};

// Re-export poll_hub_events for testing
#[doc(hidden)]
#[allow(unused_imports)] // Only used in tests
pub use outflow_generic::poll_hub_events;

// Re-export parse_amount_with_u64_limit for testing
#[doc(hidden)]
#[allow(unused_imports)] // Only used in tests
pub use hub_mvm::parse_amount_with_u64_limit;
