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
//!   --offered-amount 1000000 \
//!   --offered-chain-id 1 \
//!   --desired-metadata 0xdef \
//!   --desired-amount 1000000 \
//!   --desired-chain-id 2 \
//!   --expiry-time 1234567890 \
//!   --issuer 0xalice \
//!   --solver 0xbob \
//!   --chain-num 1
//! ```

use anyhow::{Context, Result};
use hex;
use solver::crypto;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 || args[1] == "--help" || args[1] == "-h" {
        eprintln!("Usage: sign_intent --profile <profile> --chain-address <address> --offered-metadata <address> --offered-amount <u64> --offered-chain-id <u64> --desired-metadata <address> --desired-amount <u64> --desired-chain-id <u64> --expiry-time <u64> --issuer <address> --solver <address> --chain-num <1|2>");
        eprintln!("\nExample:");
        eprintln!("  sign_intent --profile bob-chain1 --chain-address 0x123 --offered-metadata 0xabc --offered-amount 1000000 --offered-chain-id 1 --desired-metadata 0xdef --desired-amount 1000000 --desired-chain-id 2 --expiry-time 1234567890 --issuer 0xalice --solver 0xbob --chain-num 1");
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
    let hash = crypto::get_intent_hash(
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
    let private_key = crypto::get_private_key_from_profile(&profile)?;

    // Step 3: Sign the hash
    let (signature_bytes, public_key_bytes) = crypto::sign_intent_hash(&hash, &private_key)?;

    // Step 4: Output signature as hex (with 0x prefix) to stdout
    let signature_hex = format!("0x{}", hex::encode(signature_bytes));
    println!("{}", signature_hex);

    // Output public key to stderr (needed for new authentication key format)
    // The script extracts this using grep "PUBLIC_KEY:"
    let public_key_hex = format!("0x{}", hex::encode(public_key_bytes));
    eprintln!("PUBLIC_KEY:{}", public_key_hex);

    Ok(())
}
