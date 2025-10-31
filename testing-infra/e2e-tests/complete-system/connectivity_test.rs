//! Tests for Aptos REST Client Connectivity
//!
//! These tests verify basic connectivity to Aptos chains.
//! They require the Aptos chains to be running.

use trusted_verifier::aptos_client::AptosClient;

/// Test that the Aptos client can connect to Chain 1 (Hub)
/// Why: Verify the client can communicate with running Aptos nodes
#[tokio::test]
async fn test_client_can_connect_to_chain1() {
    let client = AptosClient::new("http://127.0.0.1:8080").unwrap();
    
    // Test health check
    let result = client.health_check().await;
    assert!(result.is_ok(), "Should be able to connect to Chain 1");
}

/// Test that the Aptos client can connect to Chain 2 (Connected)
/// Why: Ensure the client works with both chain endpoints
#[tokio::test]
async fn test_client_can_connect_to_chain2() {
    let client = AptosClient::new("http://127.0.0.1:8082").unwrap();
    
    // Test health check
    let result = client.health_check().await;
    assert!(result.is_ok(), "Should be able to connect to Chain 2");
}

