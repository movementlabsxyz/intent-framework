//! Solver library for intent framework
//!
//! Provides signing, acceptance logic, and verifier communication.

pub mod acceptance;
pub mod chains;
pub mod config;
pub mod crypto;
pub mod service;
pub mod verifier_client;

// Re-export public types for convenience
pub use acceptance::{AcceptanceConfig, AcceptanceResult, DraftintentData, TokenPair};
pub use chains::{ConnectedEvmClient, ConnectedMvmClient, HubChainClient};
pub use config::{SolverConfig, SolverSigningConfig};
pub use crypto::{get_intent_hash, get_private_key_from_profile, sign_intent_hash};
pub use service::inflow::InflowService;
pub use service::outflow::OutflowService;
pub use service::signing::SigningService;
pub use service::tracker::{IntentState, IntentTracker, TrackedIntent};
pub use verifier_client::{
    ApiResponse, Approval, OutflowFulfillmentValidationResponse, PendingDraft,
    SignatureSubmission, SignatureSubmissionResponse, ValidateOutflowFulfillmentRequest,
    VerifierClient,
};

