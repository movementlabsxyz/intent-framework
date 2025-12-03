//! Chain Clients Module
//!
//! This module provides clients for interacting with hub and connected chains.
//! Supports both Move VM (hub and connected MVM chains) and EVM (connected EVM chains).

pub mod hub;
pub mod connected_mvm;
pub mod connected_evm;

// Re-export for convenience
pub use hub::{HubChainClient, IntentCreatedEvent};
pub use connected_mvm::{ConnectedMvmClient, EscrowEvent};
pub use connected_evm::{ConnectedEvmClient, EscrowInitializedEvent};

