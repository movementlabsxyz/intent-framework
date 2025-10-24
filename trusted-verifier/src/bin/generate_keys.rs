//! Ed25519 Key Generation Utility
//! 
//! This binary generates a new Ed25519 key pair for the trusted verifier service.
//! 
//! ## Usage
//! 
//! ```bash
//! # Generate new keys
//! cargo run --bin generate_keys
//! 
//! # Copy the output to your config/verifier.toml file
//! ```
//! 
//! ## Output
//! 
//! The script outputs:
//! - Private key (base64 encoded) - for signing operations
//! - Public key (base64 encoded) - for signature verification
//! 
//! Copy these values to the `[verifier]` section of your `config/verifier.toml` file.

use ed25519_dalek::SigningKey;
use rand::Rng;
use base64::{Engine as _, engine::general_purpose};

fn main() {
    // Generate a new Ed25519 key pair
    let mut rng = rand::rngs::OsRng;
    let mut secret_key_bytes = [0u8; 32];
    rng.fill(&mut secret_key_bytes);
    let signing_key = SigningKey::from_bytes(&secret_key_bytes);
    let verifying_key = signing_key.verifying_key();
    
    // Encode keys as base64
    let private_key_b64 = general_purpose::STANDARD.encode(signing_key.as_bytes());
    let public_key_b64 = general_purpose::STANDARD.encode(verifying_key.as_bytes());
    
    println!("Generated Ed25519 Key Pair:");
    println!("Private Key (base64): {}", private_key_b64);
    println!("Public Key (base64): {}", public_key_b64);
    println!();
    println!("Copy these keys to your config/verifier.toml file.");
}