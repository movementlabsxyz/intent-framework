//! Unit tests for chain clients

use serde_json::json;
use solver::chains::{ConnectedEvmClient, ConnectedMvmClient, HubChainClient};
use solver::config::{ChainConfig, EvmChainConfig};
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

fn create_test_hub_config() -> ChainConfig {
    ChainConfig {
        name: "test-hub".to_string(),
        rpc_url: "http://127.0.0.1:8080".to_string(),
        chain_id: 1,
        module_address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        profile: "test-profile".to_string(),
    }
}

fn create_test_mvm_config() -> ChainConfig {
    ChainConfig {
        name: "test-mvm".to_string(),
        rpc_url: "http://127.0.0.1:8082".to_string(),
        chain_id: 2,
        module_address: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_string(),
        profile: "test-profile".to_string(),
    }
}

fn create_test_evm_config() -> EvmChainConfig {
    EvmChainConfig {
        name: "test-evm".to_string(),
        rpc_url: "http://127.0.0.1:8545".to_string(),
        chain_id: 84532,
        escrow_contract_address: "0xcccccccccccccccccccccccccccccccccccccccc".to_string(),
        private_key_env: "TEST_PRIVATE_KEY".to_string(),
    }
}

// ============================================================================
// JSON PARSING TESTS
// ============================================================================

/// What is tested: IntentCreatedEvent deserialization
/// Why: Ensure we can parse intent creation events from hub chain
#[test]
fn test_intent_created_event_deserialization() {
    let json = json!({
        "intent_address": "0x1111111111111111111111111111111111111111",
        "intent_id": "0x2222222222222222222222222222222222222222",
        "offered_metadata": {"inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
        "offered_amount": "1000",
        "offered_chain_id": "1",
        "desired_metadata": {"inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
        "desired_amount": "2000",
        "desired_chain_id": "2",
        "requester": "0xcccccccccccccccccccccccccccccccccccccccc",
        "expiry_time": "2000000"
    });

    let event: solver::chains::hub::IntentCreatedEvent = serde_json::from_value(json).unwrap();
    assert_eq!(event.intent_address, "0x1111111111111111111111111111111111111111");
    assert_eq!(event.intent_id, "0x2222222222222222222222222222222222222222");
    assert_eq!(event.offered_amount, "1000");
    assert_eq!(event.desired_amount, "2000");
    assert_eq!(event.requester, "0xcccccccccccccccccccccccccccccccccccccccc");
}

/// What is tested: EscrowEvent deserialization (MVM)
/// Why: Ensure we can parse escrow events from connected MVM chain
#[test]
fn test_escrow_event_deserialization() {
    let json = json!({
        "escrow_id": "0x1111111111111111111111111111111111111111",
        "intent_id": "0x2222222222222222222222222222222222222222",
        "issuer": "0xcccccccccccccccccccccccccccccccccccccccc",
        "offered_metadata": {"inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
        "offered_amount": "1000",
        "desired_metadata": {"inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
        "desired_amount": "2000",
        "expiry_time": "2000000",
        "revocable": true,
        "reserved_solver": "0xdddddddddddddddddddddddddddddddddddddddd"
    });

    let event: solver::chains::connected_mvm::EscrowEvent = serde_json::from_value(json).unwrap();
    assert_eq!(event.escrow_id, "0x1111111111111111111111111111111111111111");
    assert_eq!(event.intent_id, "0x2222222222222222222222222222222222222222");
    assert_eq!(event.offered_amount, "1000");
    assert_eq!(event.reserved_solver, Some("0xdddddddddddddddddddddddddddddddddddddddd".to_string()));
}

// ============================================================================
// HUB CHAIN CLIENT TESTS
// ============================================================================

/// What is tested: HubChainClient::new() creates a client with correct config
/// Why: Ensure client initialization works correctly
#[test]
fn test_hub_client_new() {
    let config = create_test_hub_config();
    let _client = HubChainClient::new(&config).unwrap();
}

/// What is tested: get_intent_events() parses transaction events correctly
/// Why: Ensure we can extract intent creation events from transaction history
#[tokio::test]
async fn test_get_intent_events_success() {
    let mock_server = MockServer::start().await;
    let base_url = mock_server.uri().to_string();

    // Mock transaction response with LimitOrderEvent
    Mock::given(method("GET"))
        .and(path("/v1/accounts/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/transactions"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!([
            {
                "events": [
                    {
                        "type": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa::fa_intent::LimitOrderEvent",
                        "data": {
                            "intent_address": "0x1111111111111111111111111111111111111111",
                            "intent_id": "0x2222222222222222222222222222222222222222",
                            "offered_metadata": {"inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
                            "offered_amount": "1000",
                            "offered_chain_id": "1",
                            "desired_metadata": {"inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
                            "desired_amount": "2000",
                            "desired_chain_id": "2",
                            "requester": "0xcccccccccccccccccccccccccccccccccccccccc",
                            "expiry_time": "2000000",
                            "revocable": true
                        }
                    }
                ]
            }
        ])))
        .mount(&mock_server)
        .await;

    let mut config = create_test_hub_config();
    config.rpc_url = base_url;
    let client = HubChainClient::new(&config).unwrap();

    let accounts = vec!["0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string()];
    let events = client.get_intent_events(&accounts, None).await.unwrap();

    assert_eq!(events.len(), 1);
    assert_eq!(events[0].intent_id, "0x2222222222222222222222222222222222222222");
    assert_eq!(events[0].offered_amount, "1000");
}

/// What is tested: get_intent_events() handles empty transaction list
/// Why: Ensure we handle accounts with no transactions gracefully
#[tokio::test]
async fn test_get_intent_events_empty() {
    let mock_server = MockServer::start().await;
    let base_url = mock_server.uri().to_string();

    Mock::given(method("GET"))
        .and(path("/v1/accounts/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/transactions"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!([])))
        .mount(&mock_server)
        .await;

    let mut config = create_test_hub_config();
    config.rpc_url = base_url;
    let client = HubChainClient::new(&config).unwrap();

    let accounts = vec!["0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string()];
    let events = client.get_intent_events(&accounts, None).await.unwrap();

    assert_eq!(events.len(), 0);
}

// ============================================================================
// CONNECTED MVM CLIENT TESTS
// ============================================================================

/// What is tested: ConnectedMvmClient::new() creates a client with correct config
/// Why: Ensure client initialization works correctly
#[test]
fn test_mvm_client_new() {
    let config = create_test_mvm_config();
    let _client = ConnectedMvmClient::new(&config).unwrap();
}

/// What is tested: get_escrow_events() parses OracleLimitOrderEvent correctly
/// Why: Ensure we can extract escrow events from connected MVM chain
#[tokio::test]
async fn test_get_escrow_events_success() {
    let mock_server = MockServer::start().await;
    let base_url = mock_server.uri().to_string();

    Mock::given(method("GET"))
        .and(path("/v1/accounts/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/transactions"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!([
            {
                "events": [
                    {
                        "type": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb::fa_intent_with_oracle::OracleLimitOrderEvent",
                        "data": {
                            "escrow_id": "0x1111111111111111111111111111111111111111",
                            "intent_id": "0x2222222222222222222222222222222222222222",
                            "issuer": "0xcccccccccccccccccccccccccccccccccccccccc",
                            "offered_metadata": {"inner": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
                            "offered_amount": "1000",
                            "desired_metadata": {"inner": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
                            "desired_amount": "2000",
                            "expiry_time": "2000000",
                            "revocable": true,
                            "reserved_solver": "0xdddddddddddddddddddddddddddddddddddddddd"
                        }
                    }
                ]
            }
        ])))
        .mount(&mock_server)
        .await;

    let mut config = create_test_mvm_config();
    config.rpc_url = base_url;
    let client = ConnectedMvmClient::new(&config).unwrap();

    let accounts = vec!["0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string()];
    let events = client.get_escrow_events(&accounts, None).await.unwrap();

    assert_eq!(events.len(), 1);
    assert_eq!(events[0].intent_id, "0x2222222222222222222222222222222222222222");
    assert_eq!(events[0].escrow_id, "0x1111111111111111111111111111111111111111");
}

// ============================================================================
// CONNECTED EVM CLIENT TESTS
// ============================================================================

/// What is tested: ConnectedEvmClient::new() creates a client with correct config
/// Why: Ensure client initialization works correctly
#[test]
fn test_evm_client_new() {
    let config = create_test_evm_config();
    let _client = ConnectedEvmClient::new(&config).unwrap();
}

/// What is tested: get_escrow_events() parses EscrowInitialized events correctly
/// Why: Ensure we can extract escrow events from EVM chain via JSON-RPC
#[tokio::test]
async fn test_get_escrow_events_evm_success() {
    let mock_server = MockServer::start().await;
    let base_url = mock_server.uri().to_string();

    // EscrowInitialized event signature hash
    // keccak256("EscrowInitialized(uint256,address,address,address,address)")
    let event_topic = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

    Mock::given(method("POST"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "jsonrpc": "2.0",
            "result": [
                {
                    "address": "0xcccccccccccccccccccccccccccccccccccccccc",
                    "topics": [
                        event_topic,
                        "0x0000000000000000000000002222222222222222222222222222222222222222", // intent_id
                        "0x000000000000000000000000cccccccccccccccccccccccccccccccccccccccc", // escrow
                        "0x000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"  // requester
                    ],
                    "data": "0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff000000000000000000000000dddddddddddddddddddddddddddddddddddddddd", // token + reserved_solver
                    "blockNumber": "0x1000",
                    "transactionHash": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                }
            ],
            "id": 1
        })))
        .mount(&mock_server)
        .await;

    let mut config = create_test_evm_config();
    config.rpc_url = base_url;
    let client = ConnectedEvmClient::new(&config).unwrap();

    let events = client.get_escrow_events(None, None).await.unwrap();

    assert_eq!(events.len(), 1);
    // Intent ID is extracted from topic (32 bytes), so it includes padding zeros
    assert_eq!(events[0].intent_id, "0x0000000000000000000000002222222222222222222222222222222222222222");
    assert_eq!(events[0].requester, "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
    assert_eq!(events[0].token, "0xffffffffffffffffffffffffffffffffffffffff");
    assert_eq!(events[0].reserved_solver, "0xdddddddddddddddddddddddddddddddddddddddd");
}

/// What is tested: get_escrow_events() handles empty log list
/// Why: Ensure we handle no events gracefully
#[tokio::test]
async fn test_get_escrow_events_evm_empty() {
    let mock_server = MockServer::start().await;
    let base_url = mock_server.uri().to_string();

    Mock::given(method("POST"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "jsonrpc": "2.0",
            "result": [],
            "id": 1
        })))
        .mount(&mock_server)
        .await;

    let mut config = create_test_evm_config();
    config.rpc_url = base_url;
    let client = ConnectedEvmClient::new(&config).unwrap();

    let events = client.get_escrow_events(None, None).await.unwrap();

    assert_eq!(events.len(), 0);
}

/// What is tested: get_escrow_events() handles JSON-RPC errors
/// Why: Ensure we handle RPC errors correctly
#[tokio::test]
async fn test_get_escrow_events_evm_error() {
    let mock_server = MockServer::start().await;
    let base_url = mock_server.uri().to_string();

    Mock::given(method("POST"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "jsonrpc": "2.0",
            "error": {
                "code": -32000,
                "message": "Invalid filter"
            },
            "id": 1
        })))
        .mount(&mock_server)
        .await;

    let mut config = create_test_evm_config();
    config.rpc_url = base_url;
    let client = ConnectedEvmClient::new(&config).unwrap();

    let result = client.get_escrow_events(None, None).await;
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("JSON-RPC error"));
}

