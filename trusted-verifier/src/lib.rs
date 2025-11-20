//! Trusted Verifier Service Library
//!
//! This crate provides a trusted verifier service that monitors escrow deposit events
//! and triggers actions on other chains or systems.

pub mod api;
pub mod config;
pub mod crypto;
pub mod evm_client;
pub mod monitor;
pub mod mvm_client;
pub mod validator;

// Re-export commonly used types
pub use config::{ApiConfig, ChainConfig, Config, VerifierConfig};
pub use crypto::{ApprovalSignature, CryptoService};
pub use monitor::{ChainType, EscrowEvent, EventMonitor, FulfillmentEvent, RequestIntentEvent};
pub use validator::{CrossChainValidator, ValidationResult};
