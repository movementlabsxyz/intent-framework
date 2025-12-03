//! Intent signing utilities

use anyhow::{Context, Result};
use base64::{engine::general_purpose, Engine as _};
use ed25519_dalek::{Signer, SigningKey};

/// Sign an intent hash with the solver's private key
///
/// Returns a tuple of (signature_bytes, public_key_bytes)
pub fn sign_intent_hash(hash: &[u8], private_key: &[u8; 32]) -> Result<(Vec<u8>, Vec<u8>)> {
    let signing_key = SigningKey::from_bytes(private_key);
    let verifying_key = signing_key.verifying_key();
    let signature = signing_key.sign(hash);
    
    Ok((signature.to_bytes().to_vec(), verifying_key.to_bytes().to_vec()))
}

/// Get private key from Movement/Aptos profile config
///
/// Searches for `.aptos/config.yaml` starting from the current directory
/// and walking up to find the project root.
pub fn get_private_key_from_profile(profile: &str) -> Result<[u8; 32]> {
    // Get private key from Aptos config
    // Use project root .aptos/config.yaml (go up from current dir to find project root)
    let mut current_dir = std::env::current_dir().context("Failed to get current directory")?;

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
    let config_content = std::fs::read_to_string(&config_path).with_context(|| {
        format!(
            "Failed to read Aptos config file at: {}. Make sure the file exists.",
            config_path
        )
    })?;

    // Parse YAML to find the profile's private key
    // The structure is: profiles.<profile>.private_key
    let yaml: serde_yaml::Value =
        serde_yaml::from_str(&config_content).context("Failed to parse YAML config")?;

    let private_key_str = yaml["profiles"][profile]["private_key"].as_str().context(
        "Private key not found in profile. Make sure the profile exists and has a private key.",
    )?;

    // Decode private key - supports both ed25519-priv-0x<hex> format and base64
    let private_key_bytes = if private_key_str.starts_with("ed25519-priv-0x") {
        // Extract hex part after "ed25519-priv-0x"
        let hex_part = private_key_str
            .strip_prefix("ed25519-priv-0x")
            .context("Invalid private key format: expected ed25519-priv-0x<hex>")?;
        hex::decode(hex_part).context("Failed to decode private key from hex")?
    } else {
        // Try base64 decoding (legacy format)
        general_purpose::STANDARD
            .decode(private_key_str)
            .context("Failed to decode private key from base64")?
    };

    if private_key_bytes.len() != 32 {
        anyhow::bail!(
            "Invalid private key length: expected 32 bytes, got {}",
            private_key_bytes.len()
        );
    }

    let mut key_array = [0u8; 32];
    key_array.copy_from_slice(&private_key_bytes);
    Ok(key_array)
}

