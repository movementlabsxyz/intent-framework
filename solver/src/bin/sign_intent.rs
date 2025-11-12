//! Intent Signature Generation Utility
//! 
//! This binary generates an Ed25519 signature for an IntentToSign structure.
//! It calls the Move function to get the hash, then signs it with the solver's private key.
//! 
//! ## Usage
//!
//! ```bash
//! cargo run --bin sign_intent -- \
//!   --profile bob-chain1 \
//!   --chain-address 0x123 \
//!   --offered-metadata 0xabc \
//!   --offered-amount 100000000 \
//!   --offered-chain-id 1 \
//!   --desired-metadata 0xdef \
//!   --desired-amount 100000000 \
//!   --desired-chain-id 2 \
//!   --expiry-time 1234567890 \
//!   --issuer 0xalice \
//!   --solver 0xbob \
//!   --chain-num 1
//! ```

use anyhow::{Context, Result};
use ed25519_dalek::{SigningKey, Signer};
use base64::{Engine as _, engine::general_purpose};
use serde_json::Value;
use std::process::Command;
use std::str;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    
    if args.len() < 2 || args[1] == "--help" || args[1] == "-h" {
        eprintln!("Usage: sign_intent --profile <profile> --chain-address <address> --offered-metadata <address> --offered-amount <u64> --offered-chain-id <u64> --desired-metadata <address> --desired-amount <u64> --desired-chain-id <u64> --expiry-time <u64> --issuer <address> --solver <address> --chain-num <1|2>");
        eprintln!("\nExample:");
        eprintln!("  sign_intent --profile bob-chain1 --chain-address 0x123 --offered-metadata 0xabc --offered-amount 100000000 --offered-chain-id 1 --desired-metadata 0xdef --desired-amount 100000000 --desired-chain-id 2 --expiry-time 1234567890 --issuer 0xalice --solver 0xbob --chain-num 1");
        std::process::exit(1);
    }

    // Parse arguments
    let mut profile = None;
    let mut chain_address = None;
    let mut offered_metadata = None;
    let mut offered_amount = None;
    let mut offered_chain_id = None;
    let mut desired_metadata = None;
    let mut desired_amount = None;
    let mut desired_chain_id = None;
    let mut expiry_time = None;
    let mut issuer = None;
    let mut solver = None;
    let mut chain_num = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--profile" => {
                profile = Some(args[i + 1].clone());
                i += 2;
            }
            "--chain-address" => {
                chain_address = Some(args[i + 1].clone());
                i += 2;
            }
            "--offered-metadata" => {
                offered_metadata = Some(args[i + 1].clone());
                i += 2;
            }
            "--offered-amount" => {
                offered_amount = Some(args[i + 1].parse().context("Invalid offered-amount")?);
                i += 2;
            }
            "--offered-chain-id" => {
                offered_chain_id = Some(args[i + 1].parse().context("Invalid offered-chain-id")?);
                i += 2;
            }
            "--desired-metadata" => {
                desired_metadata = Some(args[i + 1].clone());
                i += 2;
            }
            "--desired-amount" => {
                desired_amount = Some(args[i + 1].parse().context("Invalid desired-amount")?);
                i += 2;
            }
            "--desired-chain-id" => {
                desired_chain_id = Some(args[i + 1].parse().context("Invalid desired-chain-id")?);
                i += 2;
            }
            "--expiry-time" => {
                expiry_time = Some(args[i + 1].parse().context("Invalid expiry-time")?);
                i += 2;
            }
            "--issuer" => {
                issuer = Some(args[i + 1].clone());
                i += 2;
            }
            "--solver" => {
                solver = Some(args[i + 1].clone());
                i += 2;
            }
            "--chain-num" => {
                chain_num = Some(args[i + 1].parse().context("Invalid chain-num")?);
                i += 2;
            }
            _ => {
                eprintln!("Unknown argument: {}", args[i]);
                std::process::exit(1);
            }
        }
    }

    let profile = profile.context("--profile is required")?;
    let chain_address = chain_address.context("--chain-address is required")?;
    let offered_metadata = offered_metadata.context("--offered-metadata is required")?;
    let offered_amount = offered_amount.context("--offered-amount is required")?;
    let offered_chain_id = offered_chain_id.context("--offered-chain-id is required")?;
    let desired_metadata = desired_metadata.context("--desired-metadata is required")?;
    let desired_amount = desired_amount.context("--desired-amount is required")?;
    let desired_chain_id = desired_chain_id.context("--desired-chain-id is required")?;
    let expiry_time = expiry_time.context("--expiry-time is required")?;
    let issuer = issuer.context("--issuer is required")?;
    let solver = solver.context("--solver is required")?;
    let chain_num = chain_num.context("--chain-num is required")?;

    // Step 1: Call Move function to get the hash
    let hash = get_intent_hash(
        &profile,
        &chain_address,
        &offered_metadata,
        offered_amount,
        offered_chain_id,
        &desired_metadata,
        desired_amount,
        desired_chain_id,
        expiry_time,
        &issuer,
        &solver,
        chain_num,
    )?;

    // Step 2: Get private key from Aptos config
    let private_key = get_private_key_from_profile(&profile)?;

    // Step 3: Sign the hash
    let signing_key = SigningKey::from_bytes(&private_key);
    let verifying_key = signing_key.verifying_key();
    let signature = signing_key.sign(&hash);
    let signature_bytes = signature.to_bytes();

    // Step 4: Output signature as hex (with 0x prefix) to stdout
    let signature_hex = format!("0x{}", hex::encode(signature_bytes));
    println!("{}", signature_hex);
    
    // Output public key to stderr (needed for new authentication key format)
    // The script extracts this using grep "PUBLIC_KEY:"
    let public_key_bytes = verifying_key.to_bytes();
    let public_key_hex = format!("0x{}", hex::encode(public_key_bytes));
    eprintln!("PUBLIC_KEY:{}", public_key_hex);

    Ok(())
}

fn get_intent_hash(
    profile: &str,
    chain_address: &str,
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
    // Determine REST port
    let rest_port = if chain_num == 1 { "8080" } else { "8082" };

    // Call Move function
    let output = Command::new("aptos")
        .args(&[
            "move", "run",
            "--profile", profile,
            "--assume-yes",
            "--function-id", &format!("0x{}::utils::get_intent_to_sign_hash", chain_address),
            "--args",
            &format!("address:{}", offered_metadata),
            &format!("u64:{}", offered_amount),
            &format!("u64:{}", offered_chain_id),
            &format!("address:{}", desired_metadata),
            &format!("u64:{}", desired_amount),
            &format!("u64:{}", desired_chain_id),
            &format!("u64:{}", expiry_time),
            &format!("address:{}", issuer),
            &format!("address:{}", solver),
        ])
        .output()
        .context("Failed to execute aptos move run")?;

    if !output.status.success() {
        let stderr = str::from_utf8(&output.stderr).unwrap_or("");
        anyhow::bail!("aptos move run failed: {}", stderr);
    }

    // Wait for transaction to be processed
    std::thread::sleep(std::time::Duration::from_secs(2));

    // Use the solver address that was passed as a parameter
    // Remove 0x prefix if present
    let solver_address = solver.strip_prefix("0x").unwrap_or(solver);

    // Query REST API for the latest transaction event
    let url = format!("http://127.0.0.1:{}/v1/accounts/{}/transactions?limit=1", rest_port, solver_address);
    let response = reqwest::blocking::get(&url)
        .context("Failed to query REST API")?
        .json::<Value>()
        .context("Failed to parse REST API response")?;

    // Extract hash from IntentHashEvent
    // The event structure: { "type": "...::utils::IntentHashEvent", "data": { "hash": "0x..." } }
    let events = response[0]["events"].as_array().context("No events found")?;
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

    anyhow::bail!("IntentHashEvent not found in transaction events. Response: {}", serde_json::to_string_pretty(&response)?);
}

fn get_private_key_from_profile(profile: &str) -> Result<[u8; 32]> {
    // Get private key from Aptos config
    // Use project root .aptos/config.yaml (go up from current dir to find project root)
    let mut current_dir = std::env::current_dir()
        .context("Failed to get current directory")?;
    
    // Try current directory and parent directories to find .aptos/config.yaml
    let mut config_path = current_dir.join(".aptos").join("config.yaml");
    let mut attempts = 0;
    while !config_path.exists() && attempts < 3 {
        if let Some(parent) = current_dir.parent() {
            current_dir = parent.to_path_buf();
            config_path = current_dir.join(".aptos").join("config.yaml");
            attempts += 1;
        } else {
            break;
        }
    }
    
    if !config_path.exists() {
        anyhow::bail!("Failed to find Aptos config file at: {}. Please ensure the config file exists in the project root.", config_path.display());
    }
    
    let config_path = config_path.to_string_lossy().to_string();

    // Read and parse YAML config
    let config_content = std::fs::read_to_string(&config_path)
        .with_context(|| format!("Failed to read Aptos config file at: {}. Make sure the file exists.", config_path))?;

    // Parse YAML to find the profile's private key
    // Note: Aptos CLI stores private keys, but they might be encrypted
    // For e2e tests, we assume the key is stored in plaintext or we use a different method
    
    // Alternative: Use aptos key extract to get the key
    // But aptos CLI doesn't have a direct command for this
    
    // For now, we'll try to extract from config.yaml
    // The structure is: profiles.<profile>.private_key
    let yaml: serde_yaml::Value = serde_yaml::from_str(&config_content)
        .context("Failed to parse YAML config")?;

    let private_key_str = yaml["profiles"][profile]["private_key"]
        .as_str()
        .context("Private key not found in profile. Make sure the profile exists and has a private key.")?;

    // Decode private key - supports both ed25519-priv-0x<hex> format and base64
    let private_key_bytes = if private_key_str.starts_with("ed25519-priv-0x") {
        // Extract hex part after "ed25519-priv-0x"
        let hex_part = private_key_str.strip_prefix("ed25519-priv-0x")
            .context("Invalid private key format: expected ed25519-priv-0x<hex>")?;
        hex::decode(hex_part)
            .context("Failed to decode private key from hex")?
    } else {
        // Try base64 decoding (legacy format)
        general_purpose::STANDARD.decode(private_key_str)
            .context("Failed to decode private key from base64")?
    };

    if private_key_bytes.len() != 32 {
        anyhow::bail!("Invalid private key length: expected 32 bytes, got {}", private_key_bytes.len());
    }

    let mut key_array = [0u8; 32];
    key_array.copy_from_slice(&private_key_bytes);
    Ok(key_array)
}

