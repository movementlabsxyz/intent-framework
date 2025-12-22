//! Unit tests for Move VM cross-chain escrow validation
//!
//! These tests verify Move VM-specific escrow validation logic, including
//! solver address matching for Move VM escrows.

use trusted_verifier::monitor::{EscrowEvent, IntentEvent};
use trusted_verifier::validator::CrossChainValidator;
#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::{
    build_test_config_with_mvm, create_default_escrow_event, create_default_intent_mvm,
    setup_mock_server_with_solver_registry, DUMMY_SOLVER_ADDR_MVM_HUB, DUMMY_SOLVER_ADDR_MVM_CON,
};

// ============================================================================
// MOVE VM ESCROW SOLVER VALIDATION TESTS
// ============================================================================

/// Test that verifier accepts escrows where reserved_solver matches hub intent solver for Move VM escrows
/// Why: Verify that solver address matching validation works correctly for successful cases
#[tokio::test]
async fn test_escrow_solver_address_matching_success() {
    // Setup mock server with solver registry
    let solver_addr = "0xsolver_mvm";
    let solver_connected_chain_mvm_addr = DUMMY_SOLVER_ADDR_MVM_CON;
    let (_mock_server, validator) = setup_mock_server_with_solver_registry(
        Some(solver_addr),
        Some(solver_connected_chain_mvm_addr),
    )
    .await;

    // Create a hub intent with a solver
    let hub_intent = IntentEvent {
        reserved_solver_addr: Some(solver_addr.to_string()),
        ..create_default_intent_mvm()
    };

    // Create an escrow with matching connected chain MVM solver address
    let escrow_match = EscrowEvent {
        reserved_solver_addr: Some(solver_connected_chain_mvm_addr.to_string()),
        ..create_default_escrow_event()
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
    let solver_addr = "0xsolver_mvm";
    let solver_connected_chain_mvm_addr = DUMMY_SOLVER_ADDR_MVM_CON;
    let different_solver_addr = "0xdifferent_solver_addr_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let (_mock_server, validator) = setup_mock_server_with_solver_registry(
        Some(solver_addr),
        Some(solver_connected_chain_mvm_addr),
    )
    .await;

    // Create a hub intent with a solver
    let hub_intent = IntentEvent {
        reserved_solver_addr: Some(solver_addr.to_string()),
        ..create_default_intent_mvm()
    };

    // Create an escrow with different solver address (doesn't match registered connected chain MVM address)
    let escrow_mismatch = EscrowEvent {
        reserved_solver_addr: Some(different_solver_addr.to_string()),
        ..create_default_escrow_event()
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
    let hub_intent_with_solver = create_default_intent_mvm();

    let escrow_without_solver = EscrowEvent {
        reserved_solver_addr: None,
        ..create_default_escrow_event()
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
        reserved_solver_addr: None,
        ..create_default_intent_mvm()
    };

    let escrow_with_solver = create_default_escrow_event();

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
