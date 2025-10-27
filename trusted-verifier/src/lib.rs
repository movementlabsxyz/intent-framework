//! Trusted Verifier Service Library
//! 
//! This crate provides a trusted verifier service that monitors escrow deposit events
//! and triggers actions on other chains or systems.

pub mod monitor;
pub mod validator;
pub mod crypto;
pub mod config;
pub mod api;
pub mod aptos_client;

// Re-export commonly used types
pub use crypto::{CryptoService, ApprovalSignature};
pub use config::{Config, ChainConfig, VerifierConfig, ApiConfig};
pub use monitor::{EventMonitor, IntentEvent, EscrowEvent};
pub use validator::{CrossChainValidator, ValidationResult};

