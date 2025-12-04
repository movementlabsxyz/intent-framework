//! Unit tests for draft intent storage
//!
//! These tests verify draft intent storage operations including CRUD,
//! FCFS signature handling, expiry, and status transitions.

use trusted_verifier::storage::draftintents::{
    DraftintentStore, DraftintentStatus,
};
use serde_json;

#[path = "mod.rs"]
mod test_helpers;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create test draft data
fn create_test_draft_data() -> serde_json::Value {
    serde_json::json!({
        "offered_metadata": "0x1::test::Token",
        "offered_amount": 100,
        "desired_metadata": "0x1::test::Token2",
        "desired_amount": 200,
    })
}

/// Get a future expiry time (far in the future)
fn future_expiry_time() -> u64 {
    9999999999
}

/// Get a past expiry time
fn past_expiry_time() -> u64 {
    1
}

// ============================================================================
// CRUD TESTS
// ============================================================================

/// Test that drafts can be added and retrieved
/// What is tested: Basic CRUD operations for draft intents
/// Why: Core functionality - drafts must be stored and retrievable
#[tokio::test]
async fn test_add_and_get_draft() {
    let store = DraftintentStore::new();
    let draft_data = create_test_draft_data();

    let draft = store
        .add_draft(
            "test-draft-1".to_string(),
            "0x123".to_string(),
            draft_data.clone(),
            future_expiry_time(),
        )
        .await;

    assert_eq!(draft.draft_id, "test-draft-1");
    assert_eq!(draft.requester_address, "0x123");
    assert_eq!(draft.status, DraftintentStatus::Pending);
    assert!(draft.signature.is_none(), "Draft should not have signature initially");

    let retrieved = store.get_draft("test-draft-1").await;
    assert!(retrieved.is_some(), "Draft should be retrievable");
    let retrieved = retrieved.unwrap();
    assert_eq!(retrieved.draft_id, "test-draft-1");
    assert_eq!(retrieved.requester_address, "0x123");
    assert_eq!(retrieved.status, DraftintentStatus::Pending);
}

/// Test that getting non-existent draft returns None
/// What is tested: Error handling for missing drafts
/// Why: API should handle missing drafts gracefully
#[tokio::test]
async fn test_get_nonexistent_draft() {
    let store = DraftintentStore::new();

    let retrieved = store.get_draft("nonexistent-draft").await;
    assert!(retrieved.is_none(), "Non-existent draft should return None");
}

// ============================================================================
// PENDING DRAFTS TESTS
// ============================================================================

/// Test that pending drafts can be retrieved
/// What is tested: get_pending_drafts returns all pending drafts
/// Why: Solvers need to poll for all pending drafts
#[tokio::test]
async fn test_get_pending_drafts() {
    let store = DraftintentStore::new();
    let draft_data = create_test_draft_data();

    store
        .add_draft(
            "draft-1".to_string(),
            "0x111".to_string(),
            draft_data.clone(),
            future_expiry_time(),
        )
        .await;

    store
        .add_draft(
            "draft-2".to_string(),
            "0x222".to_string(),
            draft_data.clone(),
            future_expiry_time(),
        )
        .await;

    let pending = store.get_pending_drafts().await;
    assert_eq!(pending.len(), 2, "Should return all pending drafts");
}

/// Test that expired drafts are excluded from pending list
/// What is tested: Expired drafts are filtered out
/// Why: Solvers should not see expired drafts
#[tokio::test]
async fn test_pending_drafts_exclude_expired() {
    let store = DraftintentStore::new();
    let draft_data = create_test_draft_data();

    // Add pending draft
    store
        .add_draft(
            "draft-pending".to_string(),
            "0x111".to_string(),
            draft_data.clone(),
            future_expiry_time(),
        )
        .await;

    // Add expired draft
    store
        .add_draft(
            "draft-expired".to_string(),
            "0x222".to_string(),
            draft_data.clone(),
            past_expiry_time(),
        )
        .await;

    let pending = store.get_pending_drafts().await;
    assert_eq!(pending.len(), 1, "Should only return pending draft");
    assert_eq!(
        pending[0].draft_id, "draft-pending",
        "Should return the pending draft, not expired"
    );
}

/// Test that signed drafts are excluded from pending list
/// What is tested: Signed drafts are filtered out
/// Why: Solvers should not see already-signed drafts
#[tokio::test]
async fn test_pending_drafts_exclude_signed() {
    let store = DraftintentStore::new();
    let draft_data = create_test_draft_data();

    // Add pending draft
    store
        .add_draft(
            "draft-pending".to_string(),
            "0x111".to_string(),
            draft_data.clone(),
            future_expiry_time(),
        )
        .await;

    // Add signed draft
    let signed_draft_id = "draft-signed".to_string();
    store
        .add_draft(
            signed_draft_id.clone(),
            "0x222".to_string(),
            draft_data.clone(),
            future_expiry_time(),
        )
        .await;

    // Sign the draft
    store
        .add_signature(
            &signed_draft_id,
            "0xsolver1".to_string(),
            "sig1".to_string(),
            "pub1".to_string(),
        )
        .await
        .unwrap();

    let pending = store.get_pending_drafts().await;
    assert_eq!(pending.len(), 1, "Should only return pending draft");
    assert_eq!(
        pending[0].draft_id, "draft-pending",
        "Should return the pending draft, not signed"
    );
}

// ============================================================================
// FCFS SIGNATURE TESTS
// ============================================================================

/// Test that first signature succeeds (FCFS)
/// What is tested: First signature is accepted
/// Why: FCFS logic - first solver to sign wins
#[tokio::test]
async fn test_fcfs_first_signature_succeeds() {
    let store = DraftintentStore::new();
    let draft_data = create_test_draft_data();

    store
        .add_draft(
            "draft-1".to_string(),
            "0x111".to_string(),
            draft_data,
            future_expiry_time(),
        )
        .await;

    // First signature should succeed
    let result = store
        .add_signature(
            "draft-1",
            "0xsolver1".to_string(),
            "sig1".to_string(),
            "pub1".to_string(),
        )
        .await;
    assert!(result.is_ok(), "First signature should succeed");

    // Verify draft is signed
    let draft = store.get_draft("draft-1").await.unwrap();
    assert_eq!(draft.status, DraftintentStatus::Signed);
    assert!(draft.signature.is_some());
    assert_eq!(draft.signature.unwrap().solver_address, "0xsolver1");
}

/// Test that second signature fails (FCFS)
/// What is tested: Later signatures are rejected
/// Why: FCFS logic - only first signature wins
#[tokio::test]
async fn test_fcfs_second_signature_fails() {
    let store = DraftintentStore::new();
    let draft_data = create_test_draft_data();

    store
        .add_draft(
            "draft-1".to_string(),
            "0x111".to_string(),
            draft_data,
            future_expiry_time(),
        )
        .await;

    // First signature succeeds
    store
        .add_signature(
            "draft-1",
            "0xsolver1".to_string(),
            "sig1".to_string(),
            "pub1".to_string(),
        )
        .await
        .unwrap();

    // Second signature should fail (FCFS)
    let result = store
        .add_signature(
            "draft-1",
            "0xsolver2".to_string(),
            "sig2".to_string(),
            "pub2".to_string(),
        )
        .await;
    assert!(result.is_err(), "Second signature should fail");
    assert!(
        result.unwrap_err().contains("already signed"),
        "Error should indicate draft already signed"
    );

    // Verify first signature is still stored
    let draft = store.get_draft("draft-1").await.unwrap();
    assert_eq!(draft.status, DraftintentStatus::Signed);
    assert_eq!(draft.signature.unwrap().solver_address, "0xsolver1");
}

/// Test that signature to non-existent draft fails
/// What is tested: Error handling for missing draft
/// Why: Should handle invalid draft_id gracefully
#[tokio::test]
async fn test_signature_nonexistent_draft() {
    let store = DraftintentStore::new();

    let result = store
        .add_signature(
            "nonexistent-draft",
            "0xsolver1".to_string(),
            "sig1".to_string(),
            "pub1".to_string(),
        )
        .await;
    assert!(result.is_err(), "Should fail for non-existent draft");
    assert!(
        result.unwrap_err().contains("not found"),
        "Error should indicate draft not found"
    );
}

/// Test that signature to expired draft fails
/// What is tested: Expired drafts cannot be signed
/// Why: Expired drafts should be rejected
#[tokio::test]
async fn test_signature_expired_draft() {
    let store = DraftintentStore::new();
    let draft_data = create_test_draft_data();

    store
        .add_draft(
            "draft-expired".to_string(),
            "0x111".to_string(),
            draft_data,
            past_expiry_time(),
        )
        .await;

    let result = store
        .add_signature(
            "draft-expired",
            "0xsolver1".to_string(),
            "sig1".to_string(),
            "pub1".to_string(),
        )
        .await;
    assert!(result.is_err(), "Should fail for expired draft");
    assert!(
        result.unwrap_err().contains("expired"),
        "Error should indicate draft expired"
    );
}

// ============================================================================
// STATUS TRANSITION TESTS
// ============================================================================

/// Test that draft status transitions from Pending to Signed
/// What is tested: Status update when signature is added
/// Why: Status must accurately reflect draft state
#[tokio::test]
async fn test_status_transition_pending_to_signed() {
    let store = DraftintentStore::new();
    let draft_data = create_test_draft_data();

    store
        .add_draft(
            "draft-1".to_string(),
            "0x111".to_string(),
            draft_data,
            future_expiry_time(),
        )
        .await;

    // Initially pending
    let draft = store.get_draft("draft-1").await.unwrap();
    assert_eq!(draft.status, DraftintentStatus::Pending);

    // Sign draft
    store
        .add_signature(
            "draft-1",
            "0xsolver1".to_string(),
            "sig1".to_string(),
            "pub1".to_string(),
        )
        .await
        .unwrap();

    // Now signed
    let draft = store.get_draft("draft-1").await.unwrap();
    assert_eq!(draft.status, DraftintentStatus::Signed);
}

// ============================================================================
// EXPIRY TESTS
// ============================================================================

/// Test that cleanup_expired marks expired drafts correctly
/// What is tested: Expired drafts are marked as expired
/// Why: Expired drafts should be cleaned up
#[tokio::test]
async fn test_cleanup_expired() {
    let store = DraftintentStore::new();
    let draft_data = create_test_draft_data();

    // Add expired draft
    store
        .add_draft(
            "draft-expired".to_string(),
            "0x111".to_string(),
            draft_data.clone(),
            past_expiry_time(),
        )
        .await;

    // Add pending draft
    store
        .add_draft(
            "draft-pending".to_string(),
            "0x222".to_string(),
            draft_data,
            future_expiry_time(),
        )
        .await;

    // Cleanup expired
    store.cleanup_expired().await;

    // Check expired draft is marked as expired
    let expired_draft = store.get_draft("draft-expired").await.unwrap();
    assert_eq!(expired_draft.status, DraftintentStatus::Expired);

    // Check pending draft is still pending
    let pending_draft = store.get_draft("draft-pending").await.unwrap();
    assert_eq!(pending_draft.status, DraftintentStatus::Pending);
}

// ============================================================================
// DATA VALIDATION TESTS
// ============================================================================

/// Test that draft with empty draft_data works
/// What is tested: Empty draft_data is handled correctly
/// Why: Edge case - should not crash on empty data
#[tokio::test]
async fn test_draft_with_empty_data() {
    let store = DraftintentStore::new();
    let empty_data = serde_json::json!({});

    let draft = store
        .add_draft(
            "draft-empty".to_string(),
            "0x111".to_string(),
            empty_data,
            future_expiry_time(),
        )
        .await;

    assert_eq!(draft.draft_id, "draft-empty");
    let retrieved = store.get_draft("draft-empty").await.unwrap();
    assert_eq!(retrieved.draft_data, serde_json::json!({}));
}

/// Test that signature timestamp is set correctly
/// What is tested: Signature timestamp is recorded
/// Why: Timestamps enable audit trail and ordering
#[tokio::test]
async fn test_signature_timestamp() {
    let store = DraftintentStore::new();
    let draft_data = create_test_draft_data();

    store
        .add_draft(
            "draft-1".to_string(),
            "0x111".to_string(),
            draft_data,
            future_expiry_time(),
        )
        .await;

    store
        .add_signature(
            "draft-1",
            "0xsolver1".to_string(),
            "sig1".to_string(),
            "pub1".to_string(),
        )
        .await
        .unwrap();

    let draft = store.get_draft("draft-1").await.unwrap();
    let signature = draft.signature.unwrap();
    assert!(signature.signature_timestamp > 0, "Timestamp should be set");
}

