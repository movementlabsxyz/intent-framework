//! Get Ethereum Address from Verifier Config
//!
//! This binary reads the verifier configuration and outputs the Ethereum address
//! derived from the ECDSA public key. This address should be used as the verifier
//! address in the IntentEscrow contract deployment.

use anyhow::Result;
use trusted_verifier::config::Config;
use trusted_verifier::crypto::CryptoService;

fn main() -> Result<()> {
    // Load config
    let config = Config::load()?;

    // Create crypto service
    let crypto = CryptoService::new(&config)?;

    // Get Ethereum address
    let eth_address = crypto.get_ethereum_address()?;

    println!("{}", eth_address);

    Ok(())
}
