//! Intent hash calculation via Move view function

use anyhow::{Context, Result};
use serde_json::Value;
use std::process::Command;
use std::str;

/// Get intent hash by calling Move view function
///
/// This function calls the on-chain `get_intent_to_sign_hash` function and
/// extracts the hash from the resulting transaction event.
pub fn get_intent_hash(
    profile: &str,
    chain_addr: &str,
    offered_metadata: &str,
    offered_amount: u64,
    offered_chain_id: u64,
    desired_metadata: &str,
    desired_amount: u64,
    desired_chain_id: u64,
    expiry_time: u64,
    issuer: &str,
    solver: &str,
    chain_num: u8,
) -> Result<Vec<u8>> {
    // Validate solver address format early (before any CLI calls)
    // Solver address must have 0x prefix (required format), then strip for API call
    let solver_addr = solver
        .strip_prefix("0x")
        .ok_or_else(|| anyhow::anyhow!(
            "Solver address must start with 0x prefix, got: '{}'",
            solver
        ))?;

    // Check if we're in testnet mode (MOVEMENT_SOLVER_PRIVATE_KEY set) or E2E mode
    let is_testnet_mode = std::env::var("MOVEMENT_SOLVER_PRIVATE_KEY").is_ok();
    
    // Determine CLI and RPC URL based on mode
    let (cli, rpc_url) = if is_testnet_mode {
        // Testnet mode: use movement CLI and testnet RPC
        let rpc = std::env::var("HUB_RPC_URL")
            .unwrap_or_else(|_| "https://testnet.movementnetwork.xyz/v1".to_string());
        ("movement", rpc)
    } else {
        // E2E mode: use aptos CLI and local RPC
        let rest_port = if chain_num == 1 { "8080" } else { "8082" };
        ("aptos", format!("http://127.0.0.1:{}/v1", rest_port))
    };

    // Build command arguments
    let function_id = format!("0x{}::utils::get_intent_to_sign_hash", chain_addr);
    let mut args = vec![
        "move".to_string(),
        "run".to_string(),
    ];
    
    // Add authentication based on mode
    if is_testnet_mode {
        // Use private key directly for testnet
        let private_key = std::env::var("MOVEMENT_SOLVER_PRIVATE_KEY")
            .context("MOVEMENT_SOLVER_PRIVATE_KEY not set")?;
        let private_key = if private_key.starts_with("0x") {
            private_key
        } else {
            format!("0x{}", private_key)
        };
        args.extend(vec![
            "--private-key".to_string(),
            private_key,
            "--url".to_string(),
            rpc_url.clone(),
        ]);
    } else {
        // Use profile for E2E tests
        args.extend(vec![
            "--profile".to_string(),
            profile.to_string(),
        ]);
    }
    
    args.extend(vec![
        "--assume-yes".to_string(),
        "--function-id".to_string(),
        function_id,
        "--args".to_string(),
        format!("address:{}", offered_metadata),
        format!("u64:{}", offered_amount),
        format!("u64:{}", offered_chain_id),
        format!("address:{}", desired_metadata),
        format!("u64:{}", desired_amount),
        format!("u64:{}", desired_chain_id),
        format!("u64:{}", expiry_time),
        format!("address:{}", issuer),
        format!("address:{}", solver),
    ]);

    // Call Move function
    let output = Command::new(cli)
        .args(&args)
        .output()
        .context(format!("Failed to execute {} move run", cli))?;

    if !output.status.success() {
        let stderr = str::from_utf8(&output.stderr).unwrap_or("");
        let stdout = str::from_utf8(&output.stdout).unwrap_or("");
        anyhow::bail!(
            "{} move run failed:\nstderr: {}\nstdout: {}",
            cli,
            stderr,
            stdout
        );
    }

    // Wait for transaction to be processed
    std::thread::sleep(std::time::Duration::from_secs(2));

    // Query REST API for the latest transaction event
    // RPC URL format: https://testnet.movementnetwork.xyz/v1
    // We need: https://testnet.movementnetwork.xyz/v1/accounts/0x.../transactions
    let base_url = rpc_url.trim_end_matches('/');
    let url = format!(
        "{}/accounts/0x{}/transactions?limit=1",
        base_url,
        solver_addr
    );
    let client = reqwest::blocking::Client::builder()
        .no_proxy()
        .build()
        .context("Failed to build HTTP client")?;
    let response = client.get(&url)
        .send()
        .context(format!("Failed to query REST API at {}", url))?
        .json::<Value>()
        .context("Failed to parse REST API response")?;

    // Extract hash from IntentHashEvent
    // The event structure: { "type": "...::utils::IntentHashEvent", "data": { "hash": "0x..." } }
    let events = response[0]["events"]
        .as_array()
        .context("No events found")?;
    for event in events {
        if let Some(event_type) = event["type"].as_str() {
            if event_type.contains("IntentHashEvent") {
                // The hash might be in different formats - try both string and array
                if let Some(hash_hex) = event["data"]["hash"].as_str() {
                    // Remove 0x prefix if present and decode hex
                    let hash_hex = hash_hex.strip_prefix("0x").unwrap_or(hash_hex);
                    let hash = hex::decode(hash_hex).context("Failed to decode hash hex")?;
                    return Ok(hash);
                } else if let Some(hash_array) = event["data"]["hash"].as_array() {
                    // If it's an array of numbers, convert to bytes
                    let hash: Result<Vec<u8>, _> = hash_array
                        .iter()
                        .map(|v| {
                            v.as_u64()
                                .and_then(|n| u8::try_from(n).ok())
                                .context("Invalid hash array element")
                        })
                        .collect();
                    return Ok(hash?);
                }
            }
        }
    }

    anyhow::bail!(
        "IntentHashEvent not found in transaction events. Response: {}",
        serde_json::to_string_pretty(&response)?
    );
}

