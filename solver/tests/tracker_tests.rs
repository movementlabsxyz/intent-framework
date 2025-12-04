//! Unit tests for intent tracker

use solver::{
    acceptance::DraftintentData, config::SolverConfig, service::tracker::IntentTracker,
    IntentState,
};

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

fn create_test_draft_data() -> DraftintentData {
    DraftintentData {
        offered_token: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        offered_amount: 1000,
        offered_chain_id: 2, // Connected chain (inflow)
        desired_token: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(),
        desired_amount: 2000,
        desired_chain_id: 1, // Hub chain
    }
}

// ============================================================================
// INTENT TRACKER TESTS
// ============================================================================

/// What is tested: IntentTracker::new() creates a tracker successfully
/// Why: Ensure tracker initialization works correctly
#[test]
fn test_intent_tracker_new() {
    let config = create_test_config();
    let _tracker = IntentTracker::new(&config).unwrap();
}

/// What is tested: add_signed_intent() stores draftintent with Signed state
/// Why: Ensure signed draftintents (not yet on-chain) are tracked correctly
#[tokio::test]
async fn test_add_signed_intent() {
    let config = create_test_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let draft_data = create_test_draft_data();
    tracker
        .add_signed_intent(
            "11111111-1111-1111-1111-111111111111".to_string(),
            draft_data.clone(),
            "0xdddddddddddddddddddddddddddddddddddddddd".to_string(),
            2000000,
        )
        .await
        .unwrap();

    // Verify intent was stored
    let tracked = tracker
        .get_intent("11111111-1111-1111-1111-111111111111")
        .await
        .unwrap();
    assert_eq!(tracked.state, IntentState::Signed);
    assert_eq!(tracked.draft_data.offered_amount, 1000);
    assert!(tracked.is_inflow); // offered_chain_id (2) != hub_chain_id (1)
}

/// What is tested: add_signed_intent() correctly identifies inflow vs outflow
/// Why: Ensure intent type classification works correctly
#[tokio::test]
async fn test_add_signed_intent_inflow_outflow() {
    let config = create_test_config();
    let tracker = IntentTracker::new(&config).unwrap();

    // Test inflow intent (tokens locked on connected chain)
    let inflow_data = DraftintentData {
        offered_chain_id: 2, // Connected chain
        ..create_test_draft_data()
    };
    tracker
        .add_signed_intent(
            "inflow-draft".to_string(),
            inflow_data,
            "0xdddddddddddddddddddddddddddddddddddddddd".to_string(),
            2000000,
        )
        .await
        .unwrap();

    // Test outflow intent (tokens locked on hub chain)
    let outflow_data = DraftintentData {
        offered_chain_id: 1, // Hub chain
        ..create_test_draft_data()
    };
    tracker
        .add_signed_intent(
            "outflow-draft".to_string(),
            outflow_data,
            "0xdddddddddddddddddddddddddddddddddddddddd".to_string(),
            2000000,
        )
        .await
        .unwrap();

    let inflow = tracker.get_intent("inflow-draft").await.unwrap();
    let outflow = tracker.get_intent("outflow-draft").await.unwrap();
    assert!(inflow.is_inflow);
    assert!(!outflow.is_inflow);
}

/// What is tested: get_intents_ready_for_fulfillment() returns only Created (on-chain) intents
/// Why: Ensure filtering by state works correctly - only on-chain intents are returned, not draftintents
#[tokio::test]
async fn test_get_intents_ready_for_fulfillment_state_filter() {
    let config = create_test_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let draft_data = create_test_draft_data();

    // Add signed draftintent (Signed state - not yet on-chain)
    tracker
        .add_signed_intent(
            "draft-1".to_string(),
            draft_data.clone(),
            "0xdddddddddddddddddddddddddddddddddddddddd".to_string(),
            2000000,
        )
        .await
        .unwrap();

    // Initially, no intents ready (still Signed state - draftintent, not yet on-chain)
    let intents = tracker.get_intents_ready_for_fulfillment(None).await;
    assert_eq!(intents.len(), 0);

    // Manually mark as Created (simulating poll_for_created_intents result)
    // This simulates the requester creating the intent on-chain
    tracker.set_intent_state("draft-1", IntentState::Created).await.unwrap();

    // Now should return intent (on-chain intent ready for fulfillment)
    let intents = tracker.get_intents_ready_for_fulfillment(None).await;
    assert_eq!(intents.len(), 1);
    assert_eq!(intents[0].draft_id, "draft-1");
}

/// What is tested: get_intents_ready_for_fulfillment() filters by inflow/outflow
/// Why: Ensure intent type filtering works correctly
#[tokio::test]
async fn test_get_intents_ready_for_fulfillment_inflow_outflow_filter() {
    let config = create_test_config();
    let tracker = IntentTracker::new(&config).unwrap();

    // Add inflow intent
    let inflow_data = DraftintentData {
        offered_chain_id: 2,
        ..create_test_draft_data()
    };
    tracker
        .add_signed_intent(
            "inflow-draft".to_string(),
            inflow_data,
            "0xdddddddddddddddddddddddddddddddddddddddd".to_string(),
            2000000,
        )
        .await
        .unwrap();

    // Add outflow intent
    let outflow_data = DraftintentData {
        offered_chain_id: 1,
        ..create_test_draft_data()
    };
    tracker
        .add_signed_intent(
            "outflow-draft".to_string(),
            outflow_data,
            "0xdddddddddddddddddddddddddddddddddddddddd".to_string(),
            2000000,
        )
        .await
        .unwrap();

    // Mark both as Created
    tracker.set_intent_state("inflow-draft", IntentState::Created).await.unwrap();
    tracker.set_intent_state("outflow-draft", IntentState::Created).await.unwrap();

    // Test inflow filter
    let inflow_intents = tracker.get_intents_ready_for_fulfillment(Some(true)).await;
    assert_eq!(inflow_intents.len(), 1);
    assert_eq!(inflow_intents[0].draft_id, "inflow-draft");

    // Test outflow filter
    let outflow_intents = tracker.get_intents_ready_for_fulfillment(Some(false)).await;
    assert_eq!(outflow_intents.len(), 1);
    assert_eq!(outflow_intents[0].draft_id, "outflow-draft");

    // Test no filter (all)
    let all_intents = tracker.get_intents_ready_for_fulfillment(None).await;
    assert_eq!(all_intents.len(), 2);
}

/// What is tested: mark_fulfilled() updates intent state
/// Why: Ensure intent state transitions work correctly
#[tokio::test]
async fn test_mark_fulfilled() {
    let config = create_test_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let draft_data = create_test_draft_data();
    tracker
        .add_signed_intent(
            "draft-1".to_string(),
            draft_data,
            "0xdddddddddddddddddddddddddddddddddddddddd".to_string(),
            2000000,
        )
        .await
        .unwrap();

    // Mark as fulfilled
    tracker.mark_fulfilled("draft-1").await.unwrap();

    let tracked = tracker.get_intent("draft-1").await.unwrap();
    assert_eq!(tracked.state, IntentState::Fulfilled);
}

/// What is tested: mark_fulfilled() errors on non-existent intent
/// Why: Ensure error handling works correctly
#[tokio::test]
async fn test_mark_fulfilled_not_found() {
    let config = create_test_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let result = tracker.mark_fulfilled("non-existent").await;
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("not found"));
}

/// What is tested: get_intent() returns None for non-existent intent
/// Why: Ensure error handling works correctly
#[tokio::test]
async fn test_get_intent_not_found() {
    let config = create_test_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let result = tracker.get_intent("non-existent").await;
    assert!(result.is_none());
}

/// What is tested: set_intent_state() errors on non-existent intent
/// Why: Ensure error handling works correctly
#[tokio::test]
async fn test_set_intent_state_not_found() {
    let config = create_test_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let result = tracker.set_intent_state("non-existent", IntentState::Created).await;
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("not found"));
}

/// What is tested: poll_for_created_intents() returns 0 when no requester addresses tracked
/// Why: Ensure early return works correctly when no intents are tracked
#[tokio::test]
async fn test_poll_for_created_intents_empty_requester_addresses() {
    let config = create_test_config();
    let tracker = IntentTracker::new(&config).unwrap();

    // No intents added, so no requester addresses tracked
    let count = tracker.poll_for_created_intents().await.unwrap();
    assert_eq!(count, 0);
}

/// What is tested: get_intents_ready_for_fulfillment() excludes Fulfilled intents
/// Why: Ensure only Created intents are returned, not Fulfilled ones
#[tokio::test]
async fn test_get_intents_ready_for_fulfillment_excludes_fulfilled() {
    let config = create_test_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let draft_data = create_test_draft_data();

    // Add two intents
    tracker
        .add_signed_intent(
            "draft-1".to_string(),
            draft_data.clone(),
            "0xdddddddddddddddddddddddddddddddddddddddd".to_string(),
            2000000,
        )
        .await
        .unwrap();

    tracker
        .add_signed_intent(
            "draft-2".to_string(),
            draft_data,
            "0xdddddddddddddddddddddddddddddddddddddddd".to_string(),
            2000000,
        )
        .await
        .unwrap();

    // Mark both as Created
    tracker.set_intent_state("draft-1", IntentState::Created).await.unwrap();
    tracker.set_intent_state("draft-2", IntentState::Created).await.unwrap();

    // Both should be returned
    let intents = tracker.get_intents_ready_for_fulfillment(None).await;
    assert_eq!(intents.len(), 2);

    // Mark one as Fulfilled
    tracker.mark_fulfilled("draft-1").await.unwrap();

    // Only Created intent should be returned (not Fulfilled)
    let intents = tracker.get_intents_ready_for_fulfillment(None).await;
    assert_eq!(intents.len(), 1);
    assert_eq!(intents[0].draft_id, "draft-2");
}

/// What is tested: get_intents_ready_for_fulfillment() returns only Created intents
/// Why: Ensure the function correctly selects intents that have been created on-chain and are ready for fulfillment,
///      even when other intents in Signed state (draftintents not yet created on-chain) also exist
#[tokio::test]
async fn test_get_intents_ready_for_fulfillment_returns_only_created() {
    let config = create_test_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let draft_data = create_test_draft_data();

    // Add signed draftintent (Signed state - not yet on-chain)
    tracker
        .add_signed_intent(
            "draft-1".to_string(),
            draft_data.clone(),
            "0xdddddddddddddddddddddddddddddddddddddddd".to_string(),
            2000000,
        )
        .await
        .unwrap();

    // Add another and mark as Created
    tracker
        .add_signed_intent(
            "draft-2".to_string(),
            draft_data,
            "0xdddddddddddddddddddddddddddddddddddddddd".to_string(),
            2000000,
        )
        .await
        .unwrap();
    tracker.set_intent_state("draft-2", IntentState::Created).await.unwrap();

    // Only Created intent should be returned (not Signed draftintent)
    let intents = tracker.get_intents_ready_for_fulfillment(None).await;
    assert_eq!(intents.len(), 1);
    assert_eq!(intents[0].draft_id, "draft-2");
}

