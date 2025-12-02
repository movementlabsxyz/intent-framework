//! Unit tests for API error handling and request logging

use serde_json::json;
use trusted_verifier::api::{ApiResponse, ApiServer};
use trusted_verifier::crypto::CryptoService;
use trusted_verifier::monitor::EventMonitor;
use trusted_verifier::validator::CrossChainValidator;
use warp::http::StatusCode;
use warp::test::request;

#[path = "mod.rs"]
mod test_helpers;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a test API server with minimal configuration
async fn create_test_api_server() -> ApiServer {
    let config = test_helpers::build_test_config_with_mvm();
    let monitor = EventMonitor::new(&config).await.unwrap();
    let validator = CrossChainValidator::new(&config).await.unwrap();
    let crypto_service = CryptoService::new(&config).unwrap();

    ApiServer::new(config, monitor, validator, crypto_service)
}

/// Create a valid draft intent request for testing
fn valid_draft_request() -> serde_json::Value {
    json!({
        "requester_address": "0x123",
        "draft_data": { "offered_metadata": "0x1::test::Token", "offered_amount": 100 },
        "expiry_time": 9999999999u64
    })
}

// ============================================================================
// DRAFT INTENT ENDPOINT TESTS
// ============================================================================

/// Test that invalid JSON in POST /draft-intent returns proper error
/// What is tested: Error handling for malformed JSON in draft intent submission
/// Why: Ensures clients get clear error messages when sending invalid JSON
#[tokio::test]
async fn test_draft_intent_invalid_json() {
    let api_server = create_test_api_server().await;
    let routes = api_server.test_routes();

    let response = request()
        .method("POST")
        .path("/draft-intent")
        .body("invalid{")
        .reply(&routes)
        .await;

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body: ApiResponse<()> = serde_json::from_slice(response.body()).unwrap();
    assert!(!body.success);
    assert!(body.error.unwrap().contains("Invalid JSON"));
}

/// Test that missing required fields return proper error
/// What is tested: Error handling for missing fields in draft intent request
/// Why: Ensures clients get clear error messages about required fields
#[tokio::test]
async fn test_draft_intent_missing_fields() {
    let api_server = create_test_api_server().await;
    let routes = api_server.test_routes();

    let invalid_request = json!({
        "requester_address": "0x123"
        // Missing draft_data and expiry_time
    });

    let response = request()
        .method("POST")
        .path("/draft-intent")
        .json(&invalid_request)
        .reply(&routes)
        .await;

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body: ApiResponse<()> = serde_json::from_slice(response.body()).unwrap();
    assert!(!body.success);
}

/// Test that valid draft intent request succeeds
/// What is tested: Valid requests still work after adding error handling
/// Why: Ensures error handling doesn't break normal functionality
#[tokio::test]
async fn test_draft_intent_valid_request() {
    let api_server = create_test_api_server().await;
    let routes = api_server.test_routes();

    let response = request()
        .method("POST")
        .path("/draft-intent")
        .json(&valid_draft_request())
        .reply(&routes)
        .await;

    assert!(response.status().is_success());
    let body: ApiResponse<serde_json::Value> = serde_json::from_slice(response.body()).unwrap();
    assert!(body.success);
    assert!(body.data.is_some());
}

/// Test that empty body returns proper error
/// What is tested: Error handling for empty request body
/// Why: Ensures clients get clear error messages for empty requests
#[tokio::test]
async fn test_draft_intent_empty_body() {
    let api_server = create_test_api_server().await;
    let routes = api_server.test_routes();

    let response = request()
        .method("POST")
        .path("/draft-intent")
        .body("")
        .reply(&routes)
        .await;

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body: ApiResponse<()> = serde_json::from_slice(response.body()).unwrap();
    assert!(!body.success);
}

// ============================================================================
// SIGNATURE SUBMISSION ENDPOINT TESTS
// ============================================================================

/// Test that invalid JSON in POST /draft-intent/:id/signature returns proper error
/// What is tested: Error handling for malformed JSON in signature submission
/// Why: Ensures clients get clear error messages when sending invalid JSON
#[tokio::test]
async fn test_signature_submission_invalid_json() {
    let api_server = create_test_api_server().await;
    let routes = api_server.test_routes();

    // Create draft first
    let create_response = request()
        .method("POST")
        .path("/draft-intent")
        .json(&valid_draft_request())
        .reply(&routes)
        .await;

    let create_body: ApiResponse<serde_json::Value> =
        serde_json::from_slice(create_response.body()).unwrap();
    let draft_id = create_body.data.as_ref().unwrap()["draft_id"]
        .as_str()
        .unwrap();

    // Test invalid JSON
    let response = request()
        .method("POST")
        .path(&format!("/draft-intent/{}/signature", draft_id))
        .body("invalid{")
        .reply(&routes)
        .await;

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body: ApiResponse<()> = serde_json::from_slice(response.body()).unwrap();
    assert!(body.error.unwrap().contains("Invalid JSON"));
}

/// Test that missing required fields in signature submission return proper error
/// What is tested: Error handling for missing fields in signature submission
/// Why: Ensures clients get clear error messages about required fields
#[tokio::test]
async fn test_signature_submission_missing_fields() {
    let api_server = create_test_api_server().await;
    let routes = api_server.test_routes();

    // Create draft first
    let create_response = request()
        .method("POST")
        .path("/draft-intent")
        .json(&valid_draft_request())
        .reply(&routes)
        .await;

    let create_body: ApiResponse<serde_json::Value> =
        serde_json::from_slice(create_response.body()).unwrap();
    let draft_id = create_body.data.as_ref().unwrap()["draft_id"]
        .as_str()
        .unwrap();

    // Test missing fields
    let invalid_request = json!({
        "solver_address": "0x456"
        // Missing signature and public_key
    });

    let response = request()
        .method("POST")
        .path(&format!("/draft-intent/{}/signature", draft_id))
        .json(&invalid_request)
        .reply(&routes)
        .await;

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body: ApiResponse<()> = serde_json::from_slice(response.body()).unwrap();
    assert!(!body.success);
}

/// Test that signature submission route doesn't match draft intent route
/// What is tested: Route matching - /draft-intent/:id/signature vs /draft-intent
/// Why: Prevents regression where sub-paths incorrectly match parent route
#[tokio::test]
async fn test_signature_route_not_confused_with_draft_route() {
    let api_server = create_test_api_server().await;
    let routes = api_server.test_routes();

    // Create draft first
    let create_response = request()
        .method("POST")
        .path("/draft-intent")
        .json(&valid_draft_request())
        .reply(&routes)
        .await;

    let create_body: ApiResponse<serde_json::Value> =
        serde_json::from_slice(create_response.body()).unwrap();
    let draft_id = create_body.data.as_ref().unwrap()["draft_id"]
        .as_str()
        .unwrap();

    // Submit a valid signature request structure to the signature endpoint
    // This should NOT return "missing requester_address" error
    let signature_request = json!({
        "solver_address": "0x456",
        "signature": format!("0x{}", "a".repeat(128)),
        "public_key": format!("0x{}", "b".repeat(64))
    });

    let response = request()
        .method("POST")
        .path(&format!("/draft-intent/{}/signature", draft_id))
        .json(&signature_request)
        .reply(&routes)
        .await;

    // Should NOT be BAD_REQUEST with "missing requester_address"
    // (that would mean it hit the wrong route)
    let body: ApiResponse<serde_json::Value> = serde_json::from_slice(response.body()).unwrap();
    if let Some(error) = &body.error {
        assert!(
            !error.contains("requester_address"),
            "Route matching bug: signature endpoint matched draft-intent route. Error: {}",
            error
        );
    }
}
