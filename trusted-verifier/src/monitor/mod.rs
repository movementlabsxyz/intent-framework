//! Event Monitoring Module
//! 
//! This module handles monitoring blockchain events from both hub and connected chains.
//! It listens for request intent creation events on the hub chain and escrow deposit events 
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
mod inflow_mvm;
mod inflow_evm;
mod outflow_mvm;
mod outflow_evm;

// Re-export public types and functions
pub use generic::{
    ChainType, EscrowApproval, EscrowEvent, EventMonitor, FulfillmentEvent, RequestIntentEvent,
};

// Re-export test utilities (used in integration tests)
#[doc(hidden)]
#[allow(unused_imports)] // Only used in tests, not in library code
pub use generic::normalize_intent_id;
