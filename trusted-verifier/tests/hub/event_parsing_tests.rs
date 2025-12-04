//! Unit tests for hub event parsing
//!
//! These tests verify that hub chain events (OracleLimitOrderEvent, LimitOrderEvent)
//! are correctly parsed and populate all required fields in IntentEvent.

use serde_json::json;
use trusted_verifier::monitor::EventMonitor;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};
#[path = "../mod.rs"]
mod test_helpers;
use test_helpers::build_test_config_with_mvm;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a mock OracleLimitOrderEvent JSON response
fn create_mock_oracle_limit_order_event(
    intent_id: &str,
    requester_address_connected_chain: Option<&str>,
) -> serde_json::Value {
    let requester_addr_opt = requester_address_connected_chain
        .map(|addr| {
            json!({
                "vec": [addr]
            })
        })
        .unwrap_or_else(|| json!({"vec": []}));

    // Note: The event type must contain "OracleLimitOrderEvent" to match the parsing logic
    // The parsing checks: event_type.contains("OracleLimitOrderEvent")
    json!({
        "type": "0x1::fa_intent_with_oracle::OracleLimitOrderEvent",
        "data": {
            "intent_address": "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            "intent_id": intent_id,
            "offered_metadata": {"inner": "0xoffered_meta"},
            "offered_amount": "1000",
            "offered_chain_id": "1",
            "desired_metadata": {"inner": "0xdesired_meta"},
            "desired_amount": "500",
            "desired_chain_id": "2",
            "requester": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "expiry_time": "1000000",
            "min_reported_value": "0",
            "revocable": false,
            "reserved_solver": {
                "vec": ["0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]
            },
            "requester_address_connected_chain": requester_addr_opt
        }
    })
}

/// Setup a mock server that returns OracleLimitOrderEvent in transaction events
async fn setup_mock_server_with_oracle_event(
    account_address: &str,
    requester_address_connected_chain: Option<&str>,
) -> (MockServer, EventMonitor) {
    let mock_server = MockServer::start().await;

    let event = create_mock_oracle_limit_order_event(
        "0x1111111111111111111111111111111111111111111111111111111111111111",
        requester_address_connected_chain,
    );

    let transactions_response = json!([{
        "version": "1",
        "hash": "0xtx_hash",
        "events": [{
            "type": event.get("type").unwrap(),
            "data": event.get("data").unwrap(),
            "sequence_number": "0",
            "guid": {
                "creation_number": "0",
                "account_address": account_address
            }
        }]
    }]);

    Mock::given(method("GET"))
        .and(path(format!(
            "/v1/accounts/{}/transactions",
            account_address
        )))
        .respond_with(ResponseTemplate::new(200).set_body_json(transactions_response))
        .mount(&mock_server)
        .await;

    let mut config = build_test_config_with_mvm();
    config.hub_chain.rpc_url = mock_server.uri();
    // Add 0x prefix for known_accounts (the code will strip it)
    let account_with_prefix = if account_address.starts_with("0x") {
        account_address.to_string()
    } else {
        format!("0x{}", account_address)
    };
    config.hub_chain.known_accounts = Some(vec![account_with_prefix]);

    let monitor = EventMonitor::new(&config)
        .await
        .expect("Failed to create monitor");

    (mock_server, monitor)
}

// ============================================================================
// TESTS
// ============================================================================

/// Test that poll_hub_events correctly parses OracleLimitOrderEvent and populates requester_address_connected_chain
///
/// What is tested: When an OracleLimitOrderEvent is emitted with requester_address_connected_chain,
/// poll_hub_events should parse it and include it in the IntentEvent.
///
/// Why: Verify that outflow intents have all required fields populated from the event,
/// preventing validation failures due to missing requester_address_connected_chain.
#[tokio::test]
async fn test_poll_hub_events_populates_requester_address_connected_chain() {
    let _ = tracing_subscriber::fmt::try_init();
    // Use address without 0x prefix since the code strips it
    let account_address = "1";
    let requester_address_connected_chain =
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    let (_mock_server, monitor) = setup_mock_server_with_oracle_event(
        account_address,
        Some(requester_address_connected_chain),
    )
    .await;

    // Call poll_hub_events (re-exported from monitor module for testing)
    let events = trusted_verifier::monitor::poll_hub_events(&monitor)
        .await
        .expect("poll_hub_events should succeed");

    // Verify event was parsed
    assert_eq!(events.len(), 1, "Should parse one event");
    let event = &events[0];

    // Verify requester_address_connected_chain is populated
    assert_eq!(
        event.requester_address_connected_chain,
        Some(requester_address_connected_chain.to_string()),
        "requester_address_connected_chain should be populated from event"
    );

    // Verify connected_chain_id is set correctly (desired_chain_id for outflow)
    assert_eq!(
        event.connected_chain_id,
        Some(2),
        "connected_chain_id should be set to desired_chain_id (2) for outflow intents"
    );

    // Verify other fields are populated
    assert_eq!(
        event.intent_id,
        "0x1111111111111111111111111111111111111111111111111111111111111111"
    );
    assert_eq!(
        event.reserved_solver,
        Some("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string())
    );
    assert_eq!(event.offered_amount, 1000);
    assert_eq!(event.desired_amount, 500);
}

/// Test that poll_hub_events fails validation when requester_address_connected_chain is missing for outflow intents
///
/// What is tested: When an OracleLimitOrderEvent is emitted without requester_address_connected_chain
/// but with different chain IDs (indicating outflow), the event should still be parsed but
/// validation should fail later when requester_address_connected_chain is None.
///
/// Why: Verify that missing requester_address_connected_chain is detected during validation,
/// not silently ignored.
#[tokio::test]
async fn test_poll_hub_events_handles_missing_requester_address_connected_chain() {
    let _ = tracing_subscriber::fmt::try_init();
    // Use address without 0x prefix since the code strips it
    let account_address = "2";

    // Event without requester_address_connected_chain (None)
    let (_mock_server, monitor) = setup_mock_server_with_oracle_event(
        account_address,
        None, // Missing requester_address_connected_chain
    )
    .await;

    // Call poll_hub_events (re-exported from monitor module for testing)
    let events = trusted_verifier::monitor::poll_hub_events(&monitor)
        .await
        .expect("poll_hub_events should succeed even if requester_address_connected_chain is None");

    // Verify event was parsed
    assert_eq!(events.len(), 1, "Should parse one event");
    let event = &events[0];

    // Verify requester_address_connected_chain is None
    assert_eq!(
        event.requester_address_connected_chain, None,
        "requester_address_connected_chain should be None when not in event"
    );

    // Verify connected_chain_id is still set (event parsing should work)
    assert_eq!(
        event.connected_chain_id,
        Some(2),
        "connected_chain_id should still be set from chain IDs"
    );

    // This event would fail validation later when validate_outflow_fulfillment is called
    // because requester_address_connected_chain is None but connected_chain_id is Some
}

// ============================================================================
// AMOUNT PARSING TESTS
// ============================================================================

/// Test that parse_amount_with_u64_limit successfully parses valid u64 amounts
///
/// What is tested: Parsing amounts that are valid u64 values should succeed.
///
/// Why: Verify that the function correctly parses and converts valid amounts.
#[test]
fn test_parse_amount_with_u64_limit_success() {
    use trusted_verifier::monitor::parse_amount_with_u64_limit;

    // Test small value
    let result = parse_amount_with_u64_limit("1000", "test_amount");
    assert!(result.is_ok(), "Should parse small value");
    assert_eq!(result.unwrap(), 1000u64);

    // Test u64::MAX
    let result = parse_amount_with_u64_limit(&u64::MAX.to_string(), "test_amount");
    assert!(result.is_ok(), "Should parse u64::MAX");
    assert_eq!(result.unwrap(), u64::MAX);

    // Test zero
    let result = parse_amount_with_u64_limit("0", "test_amount");
    assert!(result.is_ok(), "Should parse zero");
    assert_eq!(result.unwrap(), 0u64);
}

/// Test that parse_amount_with_u64_limit rejects amounts exceeding u64::MAX
///
/// What is tested: Parsing amounts that exceed u64::MAX should fail with a clear error.
///
/// Why: Verify that the function correctly validates the Move contract constraint.
#[test]
fn test_parse_amount_with_u64_limit_exceeds_max() {
    use trusted_verifier::monitor::parse_amount_with_u64_limit;

    // Test u64::MAX + 1
    let amount_exceeding = (u64::MAX as u128 + 1).to_string();
    let result = parse_amount_with_u64_limit(&amount_exceeding, "test_amount");

    assert!(result.is_err(), "Should reject amount exceeding u64::MAX");
    let error_msg = result.unwrap_err().to_string();
    assert!(
        error_msg.contains("exceeds") && error_msg.contains("u64::MAX"),
        "Error message should mention exceeding u64::MAX. Got: {}",
        error_msg
    );
    assert!(
        error_msg.contains("Move contract") || error_msg.contains("Move contracts"),
        "Error message should mention Move contract limitation. Got: {}",
        error_msg
    );
    assert!(
        error_msg.contains("test_amount"),
        "Error message should include field name. Got: {}",
        error_msg
    );
}

/// Test that parse_amount_with_u64_limit handles invalid number strings
///
/// What is tested: Parsing invalid number strings should fail with a parse error.
///
/// Why: Verify that the function correctly handles invalid input.
#[test]
fn test_parse_amount_with_u64_limit_invalid_string() {
    use trusted_verifier::monitor::parse_amount_with_u64_limit;

    // Test invalid string
    let result = parse_amount_with_u64_limit("not_a_number", "test_amount");
    assert!(result.is_err(), "Should reject invalid number string");
    let error_msg = result.unwrap_err().to_string();
    assert!(
        error_msg.contains("parse") || error_msg.contains("Failed to parse"),
        "Error message should mention parse failure. Got: {}",
        error_msg
    );
    assert!(
        error_msg.contains("test_amount"),
        "Error message should include field name. Got: {}",
        error_msg
    );
}

/// Test that parse_amount_with_u64_limit handles large but valid u64 values
///
/// What is tested: Parsing large but valid u64 values (close to u64::MAX) should succeed.
///
/// Why: Verify that the function correctly handles large values within the limit.
#[test]
fn test_parse_amount_with_u64_limit_large_valid() {
    use trusted_verifier::monitor::parse_amount_with_u64_limit;

    // Test a large but valid value (u64::MAX - 1)
    let large_valid = (u64::MAX - 1).to_string();
    let result = parse_amount_with_u64_limit(&large_valid, "test_amount");

    assert!(result.is_ok(), "Should parse large valid value");
    assert_eq!(result.unwrap(), u64::MAX - 1);

    // Test 1 ETH in wei (10^18, well within u64::MAX)
    let one_eth_wei = "1000000000000000000";
    let result = parse_amount_with_u64_limit(one_eth_wei, "test_amount");
    assert!(result.is_ok(), "Should parse 1 ETH in wei");
    assert_eq!(result.unwrap(), 1000000000000000000u64);
}
