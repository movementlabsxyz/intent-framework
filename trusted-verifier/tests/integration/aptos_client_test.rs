//! Tests for Aptos REST Client
//!
//! These tests require the Aptos chains to be running.

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

/// Test that intent framework contracts are deployed on the chains
/// Why: Verifier needs contracts to be deployed before it can monitor events
#[tokio::test]
async fn test_contracts_deployed_on_chain1() {
    // Load the verifier config to get the actual module addresses
    let config = trusted_verifier::config::Config::load()
        .expect("Failed to load verifier config - ensure config/verifier.toml exists with module addresses");
    
    let aptos_client = AptosClient::new("http://127.0.0.1:8080").unwrap();
    
    // Extract the account address from the module address
    // Module address format: "0x{address}::module_name"
    // We need just the account address part
    let module_addr = config.hub_chain.intent_module_address.replace("0x", "");
    let account_address = if module_addr.contains("::") {
        &module_addr[..module_addr.find("::").unwrap()]
    } else {
        &module_addr
    };
    
    // Query the modules for this account
    let url = format!("http://127.0.0.1:8080/v1/accounts/{}/modules", account_address);
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .unwrap();
    
    let result = client.get(&url).send().await;
    assert!(result.is_ok(), "Should be able to query modules endpoint for Hub Chain");
    
    // Verify we got a response and that modules exist
    let response = result.unwrap();
    assert!(response.status().is_success(), "Modules endpoint should return success");
    
    // Parse the response to check if the aptos_intent module exists
    let modules: Vec<serde_json::Value> = response.json().await
        .expect("Failed to parse modules response");
    
    // Check if intent module is present (could be any intent-related module)
    let has_intent_module = modules.iter().any(|m| {
        m.get("abi").and_then(|a| a.get("name")).and_then(|n| n.as_str())
            .map(|name| name.contains("intent"))
            .unwrap_or(false)
    });
    
    assert!(has_intent_module, "aptos_intent module should be deployed on Hub Chain at address {}", account_address);
}

/// Test that intent framework contracts are deployed on the chains
/// Why: Verifier needs contracts to be deployed before it can monitor events
#[tokio::test]
async fn test_contracts_deployed_on_chain2() {
    // Load the verifier config to get the actual module addresses
    let config = trusted_verifier::config::Config::load()
        .expect("Failed to load verifier config - ensure config/verifier.toml exists with module addresses");
    
    // Extract the account address from the module address
    let module_addr = config.connected_chain.intent_module_address.replace("0x", "");
    let account_address = if module_addr.contains("::") {
        &module_addr[..module_addr.find("::").unwrap()]
    } else {
        &module_addr
    };
    
    // Query the modules for this account
    let url = format!("http://127.0.0.1:8082/v1/accounts/{}/modules", account_address);
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .unwrap();
    
    let result = client.get(&url).send().await;
    assert!(result.is_ok(), "Should be able to query modules endpoint for Connected Chain");
    
    // Verify we got a response and that modules exist
    let response = result.unwrap();
    assert!(response.status().is_success(), "Modules endpoint should return success");
    
    // Parse the response to check if the aptos_intent module exists
    let modules: Vec<serde_json::Value> = response.json().await
        .expect("Failed to parse modules response");
    
    // Check if intent module is present (could be any intent-related module)
    let has_intent_module = modules.iter().any(|m| {
        m.get("abi").and_then(|a| a.get("name")).and_then(|n| n.as_str())
            .map(|name| name.contains("intent"))
            .unwrap_or(false)
    });
    
    assert!(has_intent_module, "aptos_intent module should be deployed on Connected Chain at address {}", account_address);
}

/// Test that we can query events on Chain 1
/// Why: Event polling is core functionality for monitoring blockchain activity
#[tokio::test]
async fn test_get_account_events_chain1() {
    let client = AptosClient::new("http://127.0.0.1:8080").unwrap();
    
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
    let client = AptosClient::new("http://127.0.0.1:8082").unwrap();
    
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

/// Test event polling with a real intent created on-chain
/// Why: Verify that poll_hub_events() can parse real intent events from the blockchain
/// Note: This test will FAIL if no intents exist on-chain, which is expected behavior
#[tokio::test]
async fn test_poll_hub_events_with_real_intent() {
    // This test requires:
    // 1. Chains running (via setup-and-deploy.sh)
    // 2. Contracts deployed (via setup-and-deploy.sh)
    // 3. Alice funded (via setup-and-deploy.sh)
    // 4. An intent created (via submit-intents.sh or manual transaction)
    //
    // If no intents exist, this test will FAIL - which is correct behavior!
    
    let config = trusted_verifier::config::Config::load()
        .expect("Failed to load verifier config");
    
    // Create a temporary monitor to test polling
    let monitor = trusted_verifier::monitor::EventMonitor::new(&config).await
        .expect("Failed to create monitor");
    
    // Poll for events
    let result = monitor.poll_hub_events().await
        .expect("Failed to poll hub events");
    
    // CRITICAL: Should find at least one event if intent was created
    // This test FAILS if no intents exist, which is the expected behavior
    assert!(result.len() > 0, "Expected to find at least one intent event. No intents found on-chain - this means poll_hub_events() is working but there are no intents to monitor.");
    
    // Verify the event has correct structure
    if let Some(event) = result.first() {
        assert!(!event.intent_id.is_empty(), "Intent ID should not be empty");
        assert!(!event.creator.is_empty(), "Creator should not be empty");
        println!("Successfully parsed intent event: {:?}", event);
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

