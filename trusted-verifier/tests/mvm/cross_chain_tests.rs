//! Unit tests for Move VM cross-chain escrow validation
//!
//! These tests verify Move VM-specific escrow validation logic, including
//! solver address matching for Move VM escrows.

use trusted_verifier::monitor::{EscrowEvent, RequestIntentEvent};
use trusted_verifier::validator::CrossChainValidator;
#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::{
    build_test_config_with_mvm, create_base_escrow_event, create_base_request_intent_mvm,
};

// ============================================================================
// MOVE VM ESCROW SOLVER VALIDATION TESTS
// ============================================================================

/// Test that verifier accepts escrows where reserved_solver matches hub intent solver for Move VM escrows
/// Why: Verify that solver address matching validation works correctly for successful cases
#[tokio::test]
async fn test_escrow_solver_address_matching_success() {
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a hub intent with a solver
    let hub_intent = RequestIntentEvent {
        reserved_solver: Some("0xsolver_mvm".to_string()),
        ..create_base_request_intent_mvm()
    };

    // Create an escrow with matching solver address (Move VM escrow)
    let escrow_match = EscrowEvent {
        reserved_solver: Some("0xsolver_mvm".to_string()),
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_request_intent_fulfillment(
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
    let config = build_test_config_with_mvm();
    let validator = CrossChainValidator::new(&config)
        .await
        .expect("Failed to create validator");

    // Create a hub intent with a solver
    let hub_intent = RequestIntentEvent {
        reserved_solver: Some("0xsolver_mvm".to_string()),
        ..create_base_request_intent_mvm()
    };

    // Create an escrow with different solver address (Move VM escrow)
    let escrow_mismatch = EscrowEvent {
        reserved_solver: Some("0xdifferent_solver".to_string()),
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_request_intent_fulfillment(
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
    let hub_intent_with_solver = RequestIntentEvent {
        reserved_solver: Some("0xsolver_mvm".to_string()),
        ..create_base_request_intent_mvm()
    };

    let escrow_without_solver = EscrowEvent {
        reserved_solver: None,
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_request_intent_fulfillment(
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
    let hub_intent_without_solver = RequestIntentEvent {
        reserved_solver: None,
        ..create_base_request_intent_mvm()
    };

    let escrow_with_solver = EscrowEvent {
        reserved_solver: Some("0xsolver_mvm".to_string()),
        ..create_base_escrow_event()
    };

    let validation_result =
        trusted_verifier::validator::inflow_generic::validate_request_intent_fulfillment(
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
