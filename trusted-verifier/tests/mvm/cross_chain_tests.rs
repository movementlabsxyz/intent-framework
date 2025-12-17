//! Unit tests for Move VM cross-chain escrow validation
//!
//! These tests verify Move VM-specific escrow validation logic, including
//! solver address matching for Move VM escrows.

use serde_json::json;
use trusted_verifier::config::Config;
use trusted_verifier::monitor::{EscrowEvent, IntentEvent};
use trusted_verifier::validator::CrossChainValidator;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};
#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::{
    build_test_config_with_mvm, create_base_escrow_event, create_base_intent_mvm,
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Build a test config with a mock server URL
fn build_test_config_with_mock_server(mock_server_url: &str) -> Config {
    let mut config = build_test_config_with_mvm();
    config.hub_chain.rpc_url = mock_server_url.to_string();
    config
}

/// Helper to create a mock SolverRegistry resource response with MVM address
fn create_solver_registry_resource_with_mvm_address(
    registry_address: &str,
    solver_address: &str,
    connected_chain_mvm_address: Option<&str>,
) -> serde_json::Value {
    let solver_entry = if let Some(mvm_addr) = connected_chain_mvm_address {
        json!({
            "key": solver_address,
            "value": {
                "public_key": [1, 2, 3, 4],
                "connected_chain_evm_address": {"vec": []},
                "connected_chain_mvm_address": {"vec": [mvm_addr]},
                "registered_at": 1234567890
            }
        })
    } else {
        json!({
            "key": solver_address,
            "value": {
                "public_key": [1, 2, 3, 4],
                "connected_chain_evm_address": {"vec": []},
                "connected_chain_mvm_address": {"vec": []},
                "registered_at": 1234567890
            }
        })
    };

    json!([{
        "type": format!("{}::solver_registry::SolverRegistry", registry_address),
        "data": {
            "solvers": {
                "data": [solver_entry]
            }
        }
    }])
}

/// Setup a mock server with solver registry for MVM tests
async fn setup_mock_server_with_solver_registry(
    solver_address: Option<&str>,
    connected_chain_mvm_address: Option<&str>,
) -> (MockServer, CrossChainValidator) {
    let mock_server = MockServer::start().await;
    let registry_address = "0x1";

    if let Some(solver_addr) = solver_address {
        let resources_response = create_solver_registry_resource_with_mvm_address(
            registry_address,
            solver_addr,
            connected_chain_mvm_address,
        );

        Mock::given(method("GET"))
            .and(path(format!("/v1/accounts/{}/resources", registry_address)))
            .respond_with(ResponseTemplate::new(200).set_body_json(resources_response))
            .mount(&mock_server)
            .await;
    }

    let config = build_test_config_with_mock_server(&mock_server.uri());
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    (mock_server, validator)
}

// ============================================================================
// MOVE VM ESCROW SOLVER VALIDATION TESTS
// ============================================================================

/// Test that verifier accepts escrows where reserved_solver matches hub intent solver for Move VM escrows
/// Why: Verify that solver address matching validation works correctly for successful cases
#[tokio::test]
async fn test_escrow_solver_address_matching_success() {
    // Setup mock server with solver registry
    let solver_address = "0xsolver_mvm";
    let connected_chain_mvm_address = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let (_mock_server, validator) = setup_mock_server_with_solver_registry(
        Some(solver_address),
        Some(connected_chain_mvm_address),
    )
    .await;

    // Create a hub intent with a solver
    let hub_intent = IntentEvent {
        reserved_solver: Some(solver_address.to_string()),
        ..create_base_intent_mvm()
    };

    // Create an escrow with matching connected chain MVM solver address
    let escrow_match = EscrowEvent {
        reserved_solver: Some(connected_chain_mvm_address.to_string()),
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent,
            &escrow_match,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        validation_result.valid,
        "Validation should pass when solver addresses match"
    );
    assert!(
        !validation_result.message.contains("solver")
            || validation_result.message.contains("successful"),
        "Error message should not mention solver mismatch when addresses match"
    );
}

/// Test that verifier rejects escrows where reserved_solver doesn't match hub intent solver for Move VM escrows
/// Why: Verify that solver address mismatch validation works correctly
#[tokio::test]
async fn test_escrow_solver_address_mismatch_rejection() {
    // Setup mock server with solver registry
    let solver_address = "0xsolver_mvm";
    let connected_chain_mvm_address = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let different_solver_address = "0xdifferent_solver_address_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let (_mock_server, validator) = setup_mock_server_with_solver_registry(
        Some(solver_address),
        Some(connected_chain_mvm_address),
    )
    .await;

    // Create a hub intent with a solver
    let hub_intent = IntentEvent {
        reserved_solver: Some(solver_address.to_string()),
        ..create_base_intent_mvm()
    };

    // Create an escrow with different solver address (doesn't match registered connected chain MVM address)
    let escrow_mismatch = EscrowEvent {
        reserved_solver: Some(different_solver_address.to_string()),
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent,
            &escrow_mismatch,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        !validation_result.valid,
        "Validation should fail when solver addresses don't match"
    );
    assert!(
        validation_result.message.contains("does not match"),
        "Error message should mention solver addresses do not match"
    );
}

/// Test that verifier rejects escrows when one has reserved_solver and the other doesn't for Move VM escrows
/// Why: Verify that reservation mismatch validation works correctly
#[tokio::test]
async fn test_escrow_solver_reservation_mismatch_rejection() {
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Test case 1: Hub intent has solver, escrow doesn't
    let hub_intent_with_solver = IntentEvent {
        reserved_solver: Some("0xsolver_mvm".to_string()),
        ..create_base_intent_mvm()
    };

    let escrow_without_solver = EscrowEvent {
        reserved_solver: None,
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent_with_solver,
            &escrow_without_solver,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        !validation_result.valid,
        "Validation should fail when hub intent has solver but escrow doesn't"
    );
    assert!(
        validation_result.message.contains("reservation mismatch"),
        "Error message should mention reservation mismatch"
    );

    // Test case 2: Escrow has solver, hub intent doesn't
    let hub_intent_without_solver = IntentEvent {
        reserved_solver: None,
        ..create_base_intent_mvm()
    };

    let escrow_with_solver = EscrowEvent {
        reserved_solver: Some("0xsolver_mvm".to_string()),
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_intent_fulfillment(
            &validator,
            &hub_intent_without_solver,
            &escrow_with_solver,
        )
        .await
        .expect("Validation should complete without error");

    assert!(
        !validation_result.valid,
        "Validation should fail when escrow has solver but hub intent doesn't"
    );
    assert!(
        validation_result.message.contains("reservation mismatch"),
        "Error message should mention reservation mismatch"
    );
}
