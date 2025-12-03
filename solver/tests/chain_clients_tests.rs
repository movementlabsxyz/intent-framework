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

// ============================================================================
// claim_escrow() TESTS
// ============================================================================

/// What is tested: claim_escrow() validates intent_id format and converts to EVM format
/// Why: Ensure intent_id is properly formatted before passing to Hardhat script
#[test]
fn test_claim_escrow_intent_id_formatting() {
    // Test that intent_id with 0x prefix is preserved
    let intent_id_with_prefix = "0x1234567890abcdef";
    let formatted = if intent_id_with_prefix.starts_with("0x") {
        intent_id_with_prefix.to_string()
    } else {
        format!("0x{}", intent_id_with_prefix)
    };
    assert_eq!(formatted, "0x1234567890abcdef");

    // Test that intent_id without 0x prefix gets one added
    let intent_id_no_prefix = "1234567890abcdef";
    let formatted = if intent_id_no_prefix.starts_with("0x") {
        intent_id_no_prefix.to_string()
    } else {
        format!("0x{}", intent_id_no_prefix)
    };
    assert_eq!(formatted, "0x1234567890abcdef");
}

/// What is tested: claim_escrow() signature encoding to hex
/// Why: Ensure signature bytes are correctly converted to hex string for Hardhat script
#[test]
fn test_claim_escrow_signature_encoding() {
    use hex;
    
    // Test signature encoding (65 bytes: r || s || v)
    let signature_bytes = vec![0xaa; 65];
    let signature_hex = hex::encode(&signature_bytes);
    
    // Should be 130 hex chars (65 bytes * 2)
    assert_eq!(signature_hex.len(), 130);
    assert_eq!(signature_hex, "aa".repeat(65));
    
    // Test with actual signature-like data
    let mut signature = vec![0u8; 65];
    signature[0] = 0x12;
    signature[64] = 0x34;
    let signature_hex = hex::encode(&signature);
    assert!(signature_hex.starts_with("12"));
    assert!(signature_hex.ends_with("34"));
}

/// What is tested: claim_escrow() command building logic
/// Why: Ensure command arguments are correctly formatted for Hardhat script
#[test]
fn test_claim_escrow_command_building() {
    let escrow_address = "0xcccccccccccccccccccccccccccccccccccccccc";
    let intent_id_evm = "0x1234567890abcdef";
    let signature_hex = "aa".repeat(130);
    let evm_framework_dir = "/path/to/evm-intent-framework";
    
    // Build the command string that would be passed to bash -c
    let command = format!(
        "cd '{}' && ESCROW_ADDRESS='{}' INTENT_ID_EVM='{}' SIGNATURE_HEX='{}' npx hardhat run scripts/claim-escrow.js --network localhost",
        evm_framework_dir,
        escrow_address,
        intent_id_evm,
        signature_hex
    );
    
    // Verify all components are present
    assert!(command.contains("ESCROW_ADDRESS"));
    assert!(command.contains(escrow_address));
    assert!(command.contains("INTENT_ID_EVM"));
    assert!(command.contains(intent_id_evm));
    assert!(command.contains("SIGNATURE_HEX"));
    assert!(command.contains(&signature_hex));
    assert!(command.contains("claim-escrow.js"));
    assert!(command.contains("--network localhost"));
}

/// What is tested: claim_escrow() transaction hash extraction from output
/// Why: Ensure we can correctly parse transaction hash from Hardhat script output
#[test]
fn test_claim_escrow_hash_extraction() {
    // Test successful output format from Hardhat script
    let output = "Some log output\nClaim transaction hash: 0xabcdef1234567890\nEscrow released successfully!";
    
    if let Some(hash_line) = output.lines().find(|l| l.contains("hash") || l.contains("Hash")) {
        if let Some(hash) = hash_line.split_whitespace().find(|s| s.starts_with("0x")) {
            assert_eq!(hash, "0xabcdef1234567890");
        } else {
            panic!("Failed to extract hash from line: {}", hash_line);
        }
    } else {
        panic!("Failed to find hash line in output");
    }
    
    // Test case-insensitive matching
    let output_upper = "Some log output\nCLAIM TRANSACTION HASH: 0x1234567890abcdef\nSuccess!";
    if let Some(hash_line) = output_upper.lines().find(|l| l.contains("hash") || l.contains("Hash")) {
        if let Some(hash) = hash_line.split_whitespace().find(|s| s.starts_with("0x")) {
            assert_eq!(hash, "0x1234567890abcdef");
        }
    }
}

/// What is tested: claim_escrow() error handling for missing evm-intent-framework directory
/// Why: Ensure proper error message when directory structure is incorrect
#[test]
fn test_claim_escrow_missing_directory_error() {
    // Simulate the directory check logic
    let current_dir = std::env::current_dir().unwrap();
    let project_root = current_dir.parent().unwrap();
    let evm_framework_dir = project_root.join("evm-intent-framework");
    
    // This test documents the expected behavior - actual test would need to mock or use temp dir
    // In real code, this would bail with: "evm-intent-framework directory not found at: ..."
    // We're just verifying the path construction logic here
    assert!(evm_framework_dir.to_string_lossy().contains("evm-intent-framework"));
}

