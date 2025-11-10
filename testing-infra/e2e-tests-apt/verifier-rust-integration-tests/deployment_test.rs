//! Tests for Contract Deployment Verification
//!
//! These tests verify that contracts are deployed on both chains.
//! They require contracts to be deployed via deploy-contracts.sh

use trusted_verifier::aptos_client::AptosClient;

/// Test that intent framework contracts are deployed on the chains
/// Why: Verifier needs contracts to be deployed before it can monitor events
#[tokio::test]
async fn test_contracts_deployed_on_chain1() {
    // Load the verifier config to get the actual module addresses
    let config = trusted_verifier::config::Config::load()
        .expect("Failed to load verifier config - ensure config/verifier.toml exists with module addresses");
    
    let _aptos_client = AptosClient::new("http://127.0.0.1:8080").unwrap();
    
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
    let connected_chain_apt = config.connected_chain_apt
        .as_ref()
        .expect("Connected Aptos chain must be configured for this test");
    let module_addr = connected_chain_apt.intent_module_address.replace("0x", "");
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

