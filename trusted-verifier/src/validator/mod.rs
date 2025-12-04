//! Cross-Chain Validation Module
//!
//! This module handles cross-chain validation logic, ensuring that escrow deposits
//! on the connected chain properly fulfill the conditions specified in intents
//! created on the hub chain. It provides cryptographic validation and approval
//! mechanisms for secure cross-chain operations.
//!
//! ## Security Requirements
//!
//! **CRITICAL**: All validations must verify that escrow intents are **non-revocable**
//! (`revocable = false`) before issuing any approval signatures.

// Generic shared code
mod generic;

// Flow-specific modules (chain-agnostic)
pub mod inflow_generic;
pub mod outflow_generic;

// Flow + chain specific modules
pub mod inflow_evm;
mod inflow_mvm;
mod outflow_evm;
mod outflow_mvm;

// Re-export public types and functions
#[allow(unused_imports)] // These are used in tests via trusted_verifier::validator::*
pub use generic::{
    get_chain_type_from_chain_id, normalize_address, CrossChainValidator,
    FulfillmentTransactionParams, ValidationResult,
};
pub use outflow_evm::extract_evm_fulfillment_params;
pub use outflow_generic::validate_outflow_fulfillment;
pub use outflow_mvm::extract_mvm_fulfillment_params;
// Note: validate_intent_fulfillment is used internally but not re-exported
// Use trusted_verifier::validator::inflow_generic::validate_intent_fulfillment if needed
