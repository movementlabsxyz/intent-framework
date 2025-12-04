//! Unit tests for verifier client

use serde_json::json;
use solver::{
    ApiResponse, PendingDraft, SignatureSubmission, SignatureSubmissionResponse,
    ValidateOutflowFulfillmentRequest, VerifierClient,
};
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

// ============================================================================
// JSON PARSING TESTS
// ============================================================================

/// What is tested: VerifierClient::new() creates a client with correct base URL
/// Why: Ensure client initialization works correctly
#[test]
fn test_verifier_client_new() {
    let _client = VerifierClient::new("http://127.0.0.1:3333");
    // Client should be created successfully
    // We can't easily test the internal state without exposing it, but we can test methods
    // Actual HTTP functionality tested in integration tests
}

/// What is tested: VerifierClient methods handle API response format correctly
/// Why: Ensure we correctly parse the ApiResponse<T> wrapper from verifier
#[test]
fn test_api_response_parsing() {
    // Test successful response
    let json = r#"{
        "success": true,
        "data": [
            {
                "draft_id": "11111111-1111-1111-1111-111111111111",
                "requester_address": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "draft_data": {
                    "offered_metadata": {"inner": "0xa"},
                    "offered_amount": 1000,
                    "desired_metadata": {"inner": "0xb"},
                    "desired_amount": 2000
                },
                "timestamp": 1000000,
                "expiry_time": 2000000
            }
        ],
        "error": null
    }"#;

    let response: ApiResponse<Vec<PendingDraft>> = serde_json::from_str(json).unwrap();
    assert!(response.success);
    assert!(response.data.is_some());
    assert!(response.error.is_none());

    let drafts = response.data.unwrap();
    assert_eq!(drafts.len(), 1);
    assert_eq!(
        drafts[0].draft_id,
        "11111111-1111-1111-1111-111111111111"
    );
    assert_eq!(
        drafts[0].requester_address,
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    );
}

/// What is tested: API error response parsing
/// Why: Ensure we correctly handle error responses from verifier
#[test]
fn test_api_error_response_parsing() {
    let json = r#"{
        "success": false,
        "data": null,
        "error": "Draft already signed by another solver"
    }"#;

    let response: ApiResponse<SignatureSubmissionResponse> =
        serde_json::from_str(json).unwrap();
    assert!(!response.success);
    assert!(response.data.is_none());
    assert_eq!(
        response.error,
        Some("Draft already signed by another solver".to_string())
    );
}

/// What is tested: SignatureSubmission serialization
/// Why: Ensure request format matches verifier API expectations
#[test]
fn test_signature_submission_serialization() {
    let submission = SignatureSubmission {
        solver_address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        signature: "0x".to_string() + &"a".repeat(128),
        public_key: "0x".to_string() + &"b".repeat(64),
    };

    let json = serde_json::to_string(&submission).unwrap();
    let parsed: SignatureSubmission = serde_json::from_str(&json).unwrap();

    assert_eq!(parsed.solver_address, submission.solver_address);
    assert_eq!(parsed.signature, submission.signature);
    assert_eq!(parsed.public_key, submission.public_key);
}

/// What is tested: PendingDraft deserialization with various draft_data formats
/// Why: Ensure we can handle different draft_data JSON structures from verifier
#[test]
fn test_pending_draft_deserialization() {
    let json = r#"{
        "draft_id": "11111111-1111-1111-1111-111111111111",
        "requester_address": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "draft_data": {
            "offered_metadata": {"inner": "0xa"},
            "offered_amount": 1000,
            "offered_chain_id": 1,
            "desired_metadata": {"inner": "0xb"},
            "desired_amount": 2000,
            "desired_chain_id": 2
        },
        "timestamp": 1000000,
        "expiry_time": 2000000
    }"#;

    let draft: PendingDraft = serde_json::from_str(json).unwrap();
    assert_eq!(
        draft.draft_id,
        "11111111-1111-1111-1111-111111111111"
    );
    assert_eq!(
        draft.requester_address,
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    );
    assert_eq!(draft.timestamp, 1000000);
    assert_eq!(draft.expiry_time, 2000000);

    // Verify draft_data is accessible as JSON value
    assert!(draft.draft_data.is_object());
    let draft_obj = draft.draft_data.as_object().unwrap();
    assert!(draft_obj.contains_key("offered_amount"));
    assert!(draft_obj.contains_key("desired_amount"));
}

// ============================================================================
// HTTP MOCKING TESTS
// ============================================================================

// ----------------------------------------------------------------------------
// poll_pending_drafts() tests
// ----------------------------------------------------------------------------

/// What is tested: poll_pending_drafts() successfully fetches pending drafts
/// Why: Ensure HTTP GET request works correctly and parses response
#[test]
fn test_poll_pending_drafts_success() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (_mock_server, base_url) = rt.block_on(async {
        let mock_server = MockServer::start().await;

        let response = json!({
            "success": true,
            "data": [
                {
                    "draft_id": "11111111-1111-1111-1111-111111111111",
                    "requester_address": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    "draft_data": {
                        "offered_metadata": {"inner": "0xa"},
                        "offered_amount": 1000,
                        "desired_metadata": {"inner": "0xb"},
                        "desired_amount": 2000
                    },
                    "timestamp": 1000000,
                    "expiry_time": 2000000
                }
            ],
            "error": null
        });

        Mock::given(method("GET"))
            .and(path("/draftintents/pending"))
            .respond_with(ResponseTemplate::new(200).set_body_json(response))
            .mount(&mock_server)
            .await;

        let base_url = mock_server.uri().to_string();
        (mock_server, base_url)
    });

    let client = VerifierClient::new(base_url);
    let drafts = client.poll_pending_drafts().unwrap();

    assert_eq!(drafts.len(), 1);
    assert_eq!(
        drafts[0].draft_id,
        "11111111-1111-1111-1111-111111111111"
    );
}

/// What is tested: poll_pending_drafts() handles empty list
/// Why: Ensure empty response is handled correctly
#[test]
fn test_poll_pending_drafts_empty() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (_mock_server, base_url) = rt.block_on(async {
        let mock_server = MockServer::start().await;

        let response = json!({
            "success": true,
            "data": [],
            "error": null
        });

        Mock::given(method("GET"))
            .and(path("/draftintents/pending"))
            .respond_with(ResponseTemplate::new(200).set_body_json(response))
            .mount(&mock_server)
            .await;

        let base_url = mock_server.uri().to_string();
        (mock_server, base_url)
    });

    let client = VerifierClient::new(base_url);
    let drafts = client.poll_pending_drafts().unwrap();

    assert_eq!(drafts.len(), 0);
}

/// What is tested: poll_pending_drafts() handles API error response
/// Why: Ensure error responses are properly converted to errors
#[test]
fn test_poll_pending_drafts_error() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (_mock_server, base_url) = rt.block_on(async {
        let mock_server = MockServer::start().await;

        let response = json!({
            "success": false,
            "data": null,
            "error": "Internal server error"
        });

        Mock::given(method("GET"))
            .and(path("/draftintents/pending"))
            .respond_with(ResponseTemplate::new(500).set_body_json(response))
            .mount(&mock_server)
            .await;

        let base_url = mock_server.uri().to_string();
        (mock_server, base_url)
    });

    let client = VerifierClient::new(base_url);
    let result = client.poll_pending_drafts();

    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("Internal server error"));
}

// ----------------------------------------------------------------------------
// submit_signature() tests
// ----------------------------------------------------------------------------

/// What is tested: submit_signature() successfully submits signature
/// Why: Ensure HTTP POST request works correctly and parses response
#[test]
fn test_submit_signature_success() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (_mock_server, base_url) = rt.block_on(async {
        let mock_server = MockServer::start().await;

        let response = json!({
            "success": true,
            "data": {
                "draft_id": "11111111-1111-1111-1111-111111111111",
                "status": "signed"
            },
            "error": null
        });

        Mock::given(method("POST"))
            .and(path("/draftintent/11111111-1111-1111-1111-111111111111/signature"))
            .respond_with(ResponseTemplate::new(200).set_body_json(response))
            .mount(&mock_server)
            .await;

        let base_url = mock_server.uri().to_string();
        (mock_server, base_url)
    });

    let client = VerifierClient::new(base_url);
    let submission = SignatureSubmission {
        solver_address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        signature: "0x".to_string() + &"a".repeat(128),
        public_key: "0x".to_string() + &"b".repeat(64),
    };

    let result = client
        .submit_signature("11111111-1111-1111-1111-111111111111", &submission)
        .unwrap();

    assert_eq!(result.draft_id, "11111111-1111-1111-1111-111111111111");
    assert_eq!(result.status, "signed");
}

/// What is tested: submit_signature() handles FCFS conflict (409 Conflict)
/// Why: Ensure FCFS logic is properly detected and returns appropriate error
#[test]
fn test_submit_signature_conflict() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (_mock_server, base_url) = rt.block_on(async {
        let mock_server = MockServer::start().await;

        let response = json!({
            "success": false,
            "data": null,
            "error": "Draft already signed by another solver"
        });

        Mock::given(method("POST"))
            .and(path("/draftintent/11111111-1111-1111-1111-111111111111/signature"))
            .respond_with(ResponseTemplate::new(409).set_body_json(response))
            .mount(&mock_server)
            .await;

        let base_url = mock_server.uri().to_string();
        (mock_server, base_url)
    });

    let client = VerifierClient::new(base_url);
    let submission = SignatureSubmission {
        solver_address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        signature: "0x".to_string() + &"a".repeat(128),
        public_key: "0x".to_string() + &"b".repeat(64),
    };

    let result = client.submit_signature("11111111-1111-1111-1111-111111111111", &submission);

    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Draft already signed by another solver (FCFS)"));
}

/// What is tested: submit_signature() handles other HTTP errors
/// Why: Ensure non-409 errors are handled correctly
#[test]
fn test_submit_signature_other_error() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (_mock_server, base_url) = rt.block_on(async {
        let mock_server = MockServer::start().await;

        let response = json!({
            "success": false,
            "data": null,
            "error": "Invalid signature format"
        });

        Mock::given(method("POST"))
            .and(path("/draftintent/11111111-1111-1111-1111-111111111111/signature"))
            .respond_with(ResponseTemplate::new(400).set_body_json(response))
            .mount(&mock_server)
            .await;

        let base_url = mock_server.uri().to_string();
        (mock_server, base_url)
    });

    let client = VerifierClient::new(base_url);
    let submission = SignatureSubmission {
        solver_address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        signature: "0x".to_string() + &"a".repeat(128),
        public_key: "0x".to_string() + &"b".repeat(64),
    };

    let result = client.submit_signature("11111111-1111-1111-1111-111111111111", &submission);

    assert!(result.is_err());
    let error_msg = result.unwrap_err().to_string();
    // The error might be wrapped in "Verifier API error: " prefix
    assert!(
        error_msg.contains("Invalid signature format"),
        "Error message should contain 'Invalid signature format', got: {}",
        error_msg
    );
}

// ----------------------------------------------------------------------------
// validate_outflow_fulfillment() tests
// ----------------------------------------------------------------------------

/// What is tested: validate_outflow_fulfillment() successfully validates
/// Why: Ensure HTTP POST request works correctly and parses validation response
#[test]
fn test_validate_outflow_fulfillment_success() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (_mock_server, base_url) = rt.block_on(async {
        let mock_server = MockServer::start().await;

        let response = json!({
            "success": true,
            "data": {
                "validation": {
                    "valid": true,
                    "message": "Validation passed"
                },
                "approval_signature": {
                    "signature": "base64signature=="
                }
            },
            "error": null
        });

        Mock::given(method("POST"))
            .and(path("/validate-outflow-fulfillment"))
            .respond_with(ResponseTemplate::new(200).set_body_json(response))
            .mount(&mock_server)
            .await;

        let base_url = mock_server.uri().to_string();
        (mock_server, base_url)
    });

    let client = VerifierClient::new(base_url);
    let request = ValidateOutflowFulfillmentRequest {
        transaction_hash: "0x2222222222222222222222222222222222222222222222222222222222222222"
            .to_string(),
        chain_type: "evm".to_string(),
        intent_id: Some("0x1111111111111111111111111111111111111111111111111111111111111111".to_string()),
    };

    let result = client.validate_outflow_fulfillment(&request).unwrap();

    assert!(result.validation.valid);
    assert_eq!(result.validation.message, "Validation passed");
    assert!(result.approval_signature.is_some());
    assert_eq!(
        result.approval_signature.unwrap().signature,
        "base64signature=="
    );
}

/// What is tested: validate_outflow_fulfillment() handles validation failure
/// Why: Ensure validation errors are handled correctly
#[test]
fn test_validate_outflow_fulfillment_failure() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (_mock_server, base_url) = rt.block_on(async {
        let mock_server = MockServer::start().await;

        let response = json!({
            "success": false,
            "data": null,
            "error": "Transaction does not match intent requirements"
        });

        Mock::given(method("POST"))
            .and(path("/validate-outflow-fulfillment"))
            .respond_with(ResponseTemplate::new(400).set_body_json(response))
            .mount(&mock_server)
            .await;

        let base_url = mock_server.uri().to_string();
        (mock_server, base_url)
    });

    let client = VerifierClient::new(base_url);
    let request = ValidateOutflowFulfillmentRequest {
        transaction_hash: "0x2222222222222222222222222222222222222222222222222222222222222222"
            .to_string(),
        chain_type: "evm".to_string(),
        intent_id: None,
    };

    let result = client.validate_outflow_fulfillment(&request);

    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Transaction does not match intent requirements"));
}

// ----------------------------------------------------------------------------
// get_approvals() tests
// ----------------------------------------------------------------------------

/// What is tested: get_approvals() successfully fetches approvals
/// Why: Ensure HTTP GET request works correctly and parses response
#[test]
fn test_get_approvals_success() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (_mock_server, base_url) = rt.block_on(async {
        let mock_server = MockServer::start().await;

        let response = json!({
            "success": true,
            "data": [
                {
                    "escrow_id": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                    "intent_id": "0x1111111111111111111111111111111111111111111111111111111111111111",
                    "signature": "base64signature==",
                    "timestamp": 1000000
                }
            ],
            "error": null
        });

        Mock::given(method("GET"))
            .and(path("/approvals"))
            .respond_with(ResponseTemplate::new(200).set_body_json(response))
            .mount(&mock_server)
            .await;

        let base_url = mock_server.uri().to_string();
        (mock_server, base_url)
    });

    let client = VerifierClient::new(base_url);
    let approvals = client.get_approvals().unwrap();

    assert_eq!(approvals.len(), 1);
    assert_eq!(
        approvals[0].escrow_id,
        "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    );
    assert_eq!(
        approvals[0].intent_id,
        "0x1111111111111111111111111111111111111111111111111111111111111111"
    );
    assert_eq!(approvals[0].signature, "base64signature==");
    assert_eq!(approvals[0].timestamp, 1000000);
}

/// What is tested: get_approvals() handles empty list
/// Why: Ensure empty response is handled correctly
#[test]
fn test_get_approvals_empty() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (_mock_server, base_url) = rt.block_on(async {
        let mock_server = MockServer::start().await;

        let response = json!({
            "success": true,
            "data": [],
            "error": null
        });

        Mock::given(method("GET"))
            .and(path("/approvals"))
            .respond_with(ResponseTemplate::new(200).set_body_json(response))
            .mount(&mock_server)
            .await;

        let base_url = mock_server.uri().to_string();
        (mock_server, base_url)
    });

    let client = VerifierClient::new(base_url);
    let approvals = client.get_approvals().unwrap();

    assert_eq!(approvals.len(), 0);
}

// ----------------------------------------------------------------------------
// Error handling tests
// ----------------------------------------------------------------------------

/// What is tested: HTTP methods handle network errors (connection refused)
/// Why: Ensure network errors are properly propagated
#[test]
fn test_network_error() {
    // Use a port that's definitely not listening
    let client = VerifierClient::new("http://127.0.0.1:99999");

    let result = client.poll_pending_drafts();

    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Failed to send GET /draftintents/pending request"));
}

/// What is tested: HTTP methods handle invalid JSON responses
/// Why: Ensure malformed JSON is handled gracefully
#[test]
fn test_invalid_json_response() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (_mock_server, base_url) = rt.block_on(async {
        let mock_server = MockServer::start().await;

        Mock::given(method("GET"))
            .and(path("/draftintents/pending"))
            .respond_with(ResponseTemplate::new(200).set_body_string("invalid json"))
            .mount(&mock_server)
            .await;

        let base_url = mock_server.uri().to_string();
        (mock_server, base_url)
    });

    let client = VerifierClient::new(base_url);
    let result = client.poll_pending_drafts();

    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Failed to parse GET /draftintents/pending response"));
}

