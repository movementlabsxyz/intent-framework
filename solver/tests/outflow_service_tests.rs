//! Unit tests for outflow fulfillment service
//!
//! These tests verify that the outflow service correctly handles outflow intent fulfillment,
//! including service initialization and basic functionality.

use solver::{
    service::tracker::IntentTracker,
    service::outflow::OutflowService,
};
use std::sync::Arc;

#[path = "helpers.rs"]
mod test_helpers;
use test_helpers::create_default_solver_config;

// ============================================================================
// OUTFLOW SERVICE TESTS
// ============================================================================

/// What is tested: OutflowService::new() creates a service successfully
/// Why: Ensure service initialization works correctly
#[test]
fn test_outflow_service_new() {
    let config = create_default_solver_config();
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

    let config = create_default_solver_config();
    
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

