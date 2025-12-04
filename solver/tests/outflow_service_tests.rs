//! Unit tests for outflow fulfillment service
//!
//! These tests verify that the outflow service correctly handles outflow intent fulfillment,
//! including service initialization and basic functionality.

use solver::{
    config::SolverConfig, service::tracker::IntentTracker,
    service::outflow::OutflowService,
};
use std::sync::Arc;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

fn create_test_config() -> SolverConfig {
    SolverConfig {
        service: solver::config::ServiceConfig {
            verifier_url: "http://127.0.0.1:3333".to_string(),
            polling_interval_ms: 2000,
        },
        hub_chain: solver::config::ChainConfig {
            name: "test-hub".to_string(),
            rpc_url: "http://127.0.0.1:8080".to_string(),
            chain_id: 1,
            module_address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
            profile: "test-profile".to_string(),
        },
        connected_chain: solver::config::ConnectedChainConfig::Mvm(
            solver::config::ChainConfig {
                name: "test-mvm".to_string(),
                rpc_url: "http://127.0.0.1:8082".to_string(),
                chain_id: 2,
                module_address: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(),
                profile: "test-profile".to_string(),
            },
        ),
        acceptance: solver::config::AcceptanceConfig {
            token_pairs: std::collections::HashMap::new(),
        },
        solver: solver::config::SolverSigningConfig {
            profile: "test-profile".to_string(),
            address: "0xcccccccccccccccccccccccccccccccccccccccc".to_string(),
        },
    }
}

// Helper function for creating outflow draft data (available for future tests)
#[allow(dead_code)]
fn create_test_outflow_draft_data() -> solver::acceptance::DraftintentData {
    solver::acceptance::DraftintentData {
        offered_token: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        offered_amount: 1000,
        offered_chain_id: 1, // Hub chain (outflow)
        desired_token: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(),
        desired_amount: 2000,
        desired_chain_id: 2, // Connected chain
    }
}

// ============================================================================
// OUTFLOW SERVICE TESTS
// ============================================================================

/// What is tested: OutflowService::new() creates a service successfully
/// Why: Ensure service initialization works correctly
#[test]
fn test_outflow_service_new() {
    let config = create_test_config();
    let tracker = Arc::new(IntentTracker::new(&config).unwrap());
    let _service = OutflowService::new(config, tracker).unwrap();
}

/// What is tested: poll_and_execute_transfers() returns empty list when no pending outflow intents
/// Why: Ensure the service correctly handles the case when there are no intents to process
///
/// Note: Uses explicit Runtime::block_on to avoid nested runtime issues from reqwest::Client
#[test]
fn test_poll_and_execute_transfers_empty() {
    // Create runtime in advance, then pass it into the service creation
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let config = create_test_config();
    
    // These create reqwest::Client which may internally use tokio runtime
    let tracker = Arc::new(IntentTracker::new(&config).unwrap());
    let service = OutflowService::new(config, tracker).unwrap();

    let result = rt.block_on(service.poll_and_execute_transfers()).unwrap();
    assert_eq!(result.len(), 0);
}

// Note: Integration tests for get_verifier_approval() are covered in verifier_client_tests.rs
// which test the underlying VerifierClient::validate_outflow_fulfillment() method.
// The OutflowService::get_verifier_approval() is a thin wrapper that decodes the signature,
// so testing VerifierClient directly is sufficient.

