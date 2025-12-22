//! Unit tests for intent tracker

use solver::{
    acceptance::DraftintentData, service::tracker::IntentTracker,
    IntentState,
};

#[path = "helpers.rs"]
mod test_helpers;
use test_helpers::{
    create_default_solver_config, DUMMY_DRAFT_ID, DUMMY_EXPIRY, DUMMY_INTENT_ID,
    DUMMY_REQUESTER_ADDR_EVM, DUMMY_TOKEN_ADDR_MVM_CON, DUMMY_TOKEN_ADDR_MVM_HUB,
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create default draft data for inflow intents (tokens locked on connected chain)
fn create_default_draft_data_inflow() -> DraftintentData {
    DraftintentData {
        intent_id: DUMMY_INTENT_ID.to_string(),
        offered_token: DUMMY_TOKEN_ADDR_MVM_CON.to_string(),
        offered_amount: 1000,
        offered_chain_id: 2, // Connected chain (inflow)
        desired_token: DUMMY_TOKEN_ADDR_MVM_HUB.to_string(),
        desired_amount: 2000,
        desired_chain_id: 1, // Hub chain
    }
}

/// Create default draft data for outflow intents (tokens locked on hub chain)
fn create_default_draft_data_outflow() -> DraftintentData {
    DraftintentData {
        intent_id: DUMMY_INTENT_ID.to_string(),
        offered_token: DUMMY_TOKEN_ADDR_MVM_HUB.to_string(),
        offered_amount: 1000,
        offered_chain_id: 1, // Hub chain (outflow)
        desired_token: DUMMY_TOKEN_ADDR_MVM_CON.to_string(),
        desired_amount: 2000,
        desired_chain_id: 2, // Connected chain
    }
}

// ============================================================================
// INTENT TRACKER TESTS
// ============================================================================

/// What is tested: IntentTracker::new() creates a tracker successfully
/// Why: Ensure tracker initialization works correctly
#[test]
fn test_intent_tracker_new() {
    let config = create_default_solver_config();
    let _tracker = IntentTracker::new(&config).unwrap();
}

/// What is tested: add_signed_intent() stores draftintent with Signed state
/// Why: Ensure signed draftintents (not yet on-chain) are tracked correctly
#[tokio::test]
async fn test_add_signed_intent() {
    let config = create_default_solver_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let draft_data = create_default_draft_data_inflow();
    tracker
        .add_signed_intent(
            DUMMY_DRAFT_ID.to_string(),
            draft_data.clone(),
            DUMMY_REQUESTER_ADDR_EVM.to_string(),
            DUMMY_EXPIRY,
        )
        .await
        .unwrap();

    // Verify intent was stored
    let tracked = tracker
        .get_intent(DUMMY_DRAFT_ID)
        .await
        .unwrap();
    assert_eq!(tracked.state, IntentState::Signed);
    assert_eq!(tracked.draft_data.offered_amount, 1000);
    // Verify inflow: desired_chain_id (1) == hub_chain_id (1)
    let hub_chain_id = config.hub_chain.chain_id;
    assert_eq!(tracked.draft_data.desired_chain_id, hub_chain_id);
}

/// What is tested: add_signed_intent() correctly identifies inflow vs outflow
/// Why: Ensure intent type classification works correctly
#[tokio::test]
async fn test_add_signed_intent_inflow_outflow() {
    let config = create_default_solver_config();
    let tracker = IntentTracker::new(&config).unwrap();

    // Test inflow intent (tokens locked on connected chain)
    let inflow_data = create_default_draft_data_inflow();
    tracker
        .add_signed_intent(
            "inflow-draft".to_string(),
            inflow_data,
            DUMMY_REQUESTER_ADDR_EVM.to_string(),
            DUMMY_EXPIRY,
        )
        .await
        .unwrap();

    // Test outflow intent (tokens locked on hub chain, desired on connected)
    let outflow_data = create_default_draft_data_outflow();
    tracker
        .add_signed_intent(
            "outflow-draft".to_string(),
            outflow_data,
            DUMMY_REQUESTER_ADDR_EVM.to_string(),
            DUMMY_EXPIRY,
        )
        .await
        .unwrap();

    let inflow = tracker.get_intent("inflow-draft").await.unwrap();
    let outflow = tracker.get_intent("outflow-draft").await.unwrap();
    let hub_chain_id = config.hub_chain.chain_id;
    // Inflow: desired_chain_id == hub_chain_id
    assert_eq!(inflow.draft_data.desired_chain_id, hub_chain_id);
    // Outflow: offered_chain_id == hub_chain_id
    assert_eq!(outflow.draft_data.offered_chain_id, hub_chain_id);
}

/// What is tested: get_intents_ready_for_fulfillment() returns only Created (on-chain) intents
/// Why: Ensure filtering by state works correctly - only on-chain intents are returned, not draftintents
#[tokio::test]
async fn test_get_intents_ready_for_fulfillment_state_filter() {
    let config = create_default_solver_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let draft_data = create_default_draft_data_inflow();

    // Add signed draftintent (Signed state - not yet on-chain)
    tracker
        .add_signed_intent(
            "draft-1".to_string(),
            draft_data.clone(),
            DUMMY_REQUESTER_ADDR_EVM.to_string(),
            DUMMY_EXPIRY,
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
    let config = create_default_solver_config();
    let tracker = IntentTracker::new(&config).unwrap();

    // Add inflow intent
    let inflow_data = create_default_draft_data_inflow();
    tracker
        .add_signed_intent(
            "inflow-draft".to_string(),
            inflow_data,
            DUMMY_REQUESTER_ADDR_EVM.to_string(),
            DUMMY_EXPIRY,
        )
        .await
        .unwrap();

    // Add outflow intent (offered on hub, desired on connected)
    let outflow_data = create_default_draft_data_outflow();
    tracker
        .add_signed_intent(
            "outflow-draft".to_string(),
            outflow_data,
            DUMMY_REQUESTER_ADDR_EVM.to_string(),
            DUMMY_EXPIRY,
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
    let config = create_default_solver_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let draft_data = create_default_draft_data_inflow();
    tracker
        .add_signed_intent(
            "draft-1".to_string(),
            draft_data,
            DUMMY_REQUESTER_ADDR_EVM.to_string(),
            DUMMY_EXPIRY,
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
    let config = create_default_solver_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let result = tracker.mark_fulfilled("non-existent").await;
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("not found"));
}

/// What is tested: get_intent() returns None for non-existent intent
/// Why: Ensure error handling works correctly
#[tokio::test]
async fn test_get_intent_not_found() {
    let config = create_default_solver_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let result = tracker.get_intent("non-existent").await;
    assert!(result.is_none());
}

/// What is tested: set_intent_state() errors on non-existent intent
/// Why: Ensure error handling works correctly
#[tokio::test]
async fn test_set_intent_state_not_found() {
    let config = create_default_solver_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let result = tracker.set_intent_state("non-existent", IntentState::Created).await;
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("not found"));
}

/// What is tested: poll_for_created_intents() returns 0 when no requester addresses tracked
/// Why: Ensure early return works correctly when no intents are tracked
#[tokio::test]
async fn test_poll_for_created_intents_empty_requester_addresses() {
    let config = create_default_solver_config();
    let tracker = IntentTracker::new(&config).unwrap();

    // No intents added, so no requester addresses tracked
    let count = tracker.poll_for_created_intents().await.unwrap();
    assert_eq!(count, 0);
}

/// What is tested: get_intents_ready_for_fulfillment() excludes Fulfilled intents
/// Why: Ensure only Created intents are returned, not Fulfilled ones
#[tokio::test]
async fn test_get_intents_ready_for_fulfillment_excludes_fulfilled() {
    let config = create_default_solver_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let draft_data = create_default_draft_data_inflow();

    // Add two intents
    tracker
        .add_signed_intent(
            "draft-1".to_string(),
            draft_data.clone(),
            DUMMY_REQUESTER_ADDR_EVM.to_string(),
            DUMMY_EXPIRY,
        )
        .await
        .unwrap();

    tracker
        .add_signed_intent(
            "draft-2".to_string(),
            draft_data,
            DUMMY_REQUESTER_ADDR_EVM.to_string(),
            DUMMY_EXPIRY,
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
    let config = create_default_solver_config();
    let tracker = IntentTracker::new(&config).unwrap();

    let draft_data = create_default_draft_data_inflow();

    // Add signed draftintent (Signed state - not yet on-chain)
    tracker
        .add_signed_intent(
            "draft-1".to_string(),
            draft_data.clone(),
            DUMMY_REQUESTER_ADDR_EVM.to_string(),
            DUMMY_EXPIRY,
        )
        .await
        .unwrap();

    // Add another and mark as Created
    tracker
        .add_signed_intent(
            "draft-2".to_string(),
            draft_data,
            DUMMY_REQUESTER_ADDR_EVM.to_string(),
            DUMMY_EXPIRY,
        )
        .await
        .unwrap();
    tracker.set_intent_state("draft-2", IntentState::Created).await.unwrap();

    // Only Created intent should be returned (not Signed draftintent)
    let intents = tracker.get_intents_ready_for_fulfillment(None).await;
    assert_eq!(intents.len(), 1);
    assert_eq!(intents[0].draft_id, "draft-2");
}

