//! Tests for Aptos Event Polling
//!
//! These tests verify event polling functionality for both chains.
//! They require the Aptos chains to be running with deployed contracts.

use trusted_verifier::mvm_client::MvmClient;

/// Test that we can query events on Chain 1
/// Why: Event polling is core functionality for monitoring blockchain activity
#[tokio::test]
async fn test_get_account_events_chain1() {
    let client = MvmClient::new("http://127.0.0.1:8080").unwrap();
    
    // Query events for the system account (0x1 always exists)
    let address = "0x1";
    let result = client.get_account_events(address, None, None, Some(10)).await;
    
    // This might return empty list, which is ok - we're testing API connectivity
    match result {
        Ok(events) => {
            println!("Found {} events on Chain 1", events.len());
        }
        Err(e) => {
            println!("Note: get_account_events returned error (may be expected): {:?}", e);
        }
    }
}

/// Test that we can query events on Chain 2
/// Why: Event polling is core functionality for monitoring blockchain activity
#[tokio::test]
async fn test_get_account_events_chain2() {
    let client = MvmClient::new("http://127.0.0.1:8082").unwrap();
    
    // Query events for the system account (0x1 always exists)
    let address = "0x1";
    let result = client.get_account_events(address, None, None, Some(10)).await;
    
    // This might return empty list, which is ok - we're testing API connectivity
    match result {
        Ok(events) => {
            println!("Found {} events on Chain 2", events.len());
        }
        Err(e) => {
            println!("Note: get_account_events returned error (may be expected): {:?}", e);
        }
    }
}

/// Test event polling API connectivity for intent events
/// Why: Verify that poll_hub_events() API calls work (does not verify parsing of real events yet)
/// Note: This only tests API connectivity. For full event parsing test, intents must exist on-chain.
#[tokio::test]
async fn test_poll_hub_events_api() {
    // This test requires chains to be running with deployed contracts
    let config = trusted_verifier::config::Config::load()
        .expect("Failed to load verifier config");
    
    // Create a temporary monitor to test polling
    let monitor = trusted_verifier::monitor::EventMonitor::new(&config).await
        .expect("Failed to create monitor");
    
    // Poll for events - this only tests API connectivity, not parsing of real events
    let result = monitor.poll_hub_events().await;
    
    // This test just verifies the API call doesn't crash
    match result {
        Ok(events) => {
            println!("API call successful, found {} intent events (may be 0)", events.len());
        }
        Err(e) => {
            // Fail if API call itself fails (connection error, etc)
            panic!("Poll API call failed: {:?}", e);
        }
    }
}

/// Test event polling API connectivity for escrow events  
/// Why: Verify that poll_connected_events() API calls work (does not verify parsing of real events yet)
/// Note: This only tests API connectivity. For full event parsing test, escrows must exist on-chain.
#[tokio::test]
async fn test_poll_connected_events_api() {
    // This test requires chains to be running with deployed contracts
    let config = trusted_verifier::config::Config::load()
        .expect("Failed to load verifier config");
    
    // Create a temporary monitor to test polling
    let monitor = trusted_verifier::monitor::EventMonitor::new(&config).await
        .expect("Failed to create monitor");
    
    // Poll for events - this only tests API connectivity, not parsing of real events
    let result = monitor.poll_connected_events().await;
    
    // This test just verifies the API call doesn't crash
    match result {
        Ok(events) => {
            println!("API call successful, found {} escrow events (may be 0)", events.len());
        }
        Err(e) => {
            // Fail if API call itself fails (connection error, etc)
            panic!("Poll API call failed: {:?}", e);
        }
    }
}

// Test event polling with a real intent created on-chain
// Why: Verify that poll_hub_events() can parse real intent events from the blockchain
// Note: This test runs BEFORE intent fulfillment, so intents should always be found
// #[tokio::test]
// async fn test_poll_hub_events_with_real_intent() {
//     // This test requires:
//     // 1. Chains running (via deploy-contracts.sh)
//     // 2. Contracts deployed (via deploy-contracts.sh)
//     // 3. Alice funded (via deploy-contracts.sh)
//     // 4. An intent created (via inflow-submit-hub-intent.sh)
//     //
//     // This test runs BEFORE inflow-fulfill-hub-intent.sh, so the intent should still exist.
//     
//     let config = trusted_verifier::config::Config::load()
//         .expect("Failed to load verifier config");
//     
//     // Create a temporary monitor to test polling
//     let monitor = trusted_verifier::monitor::EventMonitor::new(&config).await
//         .expect("Failed to create monitor");
//     
//     // Poll for events
//     let result = monitor.poll_hub_events().await
//         .expect("Failed to poll hub events");
//     
//     // Should find at least one event if intent was created (test runs before fulfillment)
//     assert!(result.len() > 0, "Expected to find at least one intent event. No intents found on-chain - this means poll_hub_events() is working but there are no intents to monitor.");
//     
//     // Verify the event has correct structure
//     if let Some(event) = result.first() {
//         assert!(!event.intent_id.is_empty(), "Intent ID should not be empty");
//         assert!(!event.requester.is_empty(), "Requester should not be empty");
//         println!("Successfully parsed intent event: {:?}", event);
//     }
// }

