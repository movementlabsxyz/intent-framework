//! Connected Chain Outflow Fulfillment Transaction Template Generator
//!
//! This helper builds the canonical transaction templates that solvers should
//! submit on connected chains when fulfilling outflow intents. It guarantees
//! that the `intent_id` is encoded in the payload so the verifier can link the
//! transfer back to the hub intent.

use anyhow::{Context, Result};
use clap::{Parser, ValueEnum};
use ethereum_types::U256;

#[derive(Parser, Debug)]
// Clap uses this metadata to render `--help`/`--version` output for the binary.
#[command(
    name = "connected_chain_tx_template", // Binary name shown in help output
    author,  // Populated from Cargo package metadata
    version, // Uses crate version for `--version`
    about = "Generate Move VM/EVM connected-chain transfer templates with embedded intent_id metadata"
)]
struct Args {
    /// Target connected chain type
    #[arg(long, value_enum)]
    chain: ChainType,

    /// Recipient address on the connected chain
    #[arg(long)]
    recipient: String,

    /// Amount to transfer (base units). Parsed as u64 for Move VM, U256 for EVM.
    #[arg(long)]
    amount: String,

    /// Intent ID that links the connected-chain transaction to the hub intent
    #[arg(long, value_name = "0x...")]
    intent_id: String,

    /// Metadata object address (required for Move VM transfers)
    #[arg(long)]
    metadata: Option<String>,
}

#[derive(Copy, Clone, Debug, ValueEnum)]
enum ChainType {
    Mvm,
    Evm,
}

fn main() -> Result<()> {
    let args = Args::parse();

    match args.chain {
        ChainType::Mvm => generate_mvm_template(&args),
        ChainType::Evm => generate_evm_template(&args),
    }
}

/// Generates Move VM CLI command to call the on-chain transfer_with_intent_id function.
///
/// This function calls the on-chain utils::transfer_with_intent_id() entry function
/// which includes intent_id as a parameter so the verifier can extract it from the
/// transaction payload when querying by transaction hash.
///
/// **Why this approach differs from EVM:**
/// Move VM allows us to create a contract function that transfers tokens from the solver's
/// account to the recipient in one call. This is possible because Move VM's
/// `primary_fungible_store` framework supports withdrawing from one account and depositing
/// to another within a single function call. By including intent_id as an explicit parameter
/// in this custom function, we ensure it's part of the transaction payload and can be
/// extracted by the verifier. In contrast, EVM cannot use a contract function to transfer
/// standard ERC20 tokens from the solver's account (without requiring approval/transferFrom),
/// so the solver must call transfer() directly from their account and append intent_id as
/// extra calldata.
fn generate_mvm_template(args: &Args) -> Result<()> {
    let metadata = args
        .metadata
        .as_ref()
        .context("--metadata is required for --chain mvm")?;

    // Normalize all addresses to lowercase hex with 0x prefix
    let metadata_addr = normalize_address(metadata)?;
    let recipient_addr = normalize_address(&args.recipient)?;
    let intent_id_addr = normalize_address(&args.intent_id)?;

    // Parse amount as u64 for Move VM (base units)
    let amount: u64 = args
        .amount
        .parse()
        .context("--amount must be a u64 when --chain mvm")?;

    println!("=== Connected Move VM Chain : Outflow fulfill transaction ===\n");
    println!("Recipient: {}", recipient_addr);
    println!("Amount   : {} (u64 base units)", amount);
    println!("Intent ID: {}", intent_id_addr);
    println!("\n{}", "- ".repeat(30));
    println!("Call the on-chain transfer_with_intent_id() function:");
    println!();
    println!("  aptos move run --profile <solver-profile> \\");
    println!("      --function-id <module_address>::utils::transfer_with_intent_id \\");
    println!(
        "      --args address:{} address:{} u64:{} address:{}",
        recipient_addr, metadata_addr, amount, intent_id_addr
    );
    println!(
        "\n  Replace <solver-profile> with your Aptos CLI profile name (e.g., 'solver-chain2')"
    );
    println!("  Replace <module_address> with the deployed module address on the connected chain");
    println!("\n  The function will:");
    println!("  - Transfer tokens from your account to the recipient address");
    println!("  - Include intent_id in the transaction payload for verifier tracking\n");

    Ok(())
}

/// Generates an EVM transaction data payload for ERC20 transfer with intent_id metadata.
///
/// The payload follows the format:
/// - Function selector: transfer(address,uint256) = 0xa9059cbb
/// - to address: 32 bytes (right-padded)
/// - amount: 32 bytes
/// - intent_id: 32 bytes (metadata appended after function parameters)
///
/// The ERC20 contract ignores the extra intent_id bytes, but they remain in the transaction
/// data and are verifiable on-chain by the verifier.
///
/// **Why this approach differs from Aptos:**
/// In EVM with standard ERC20, a contract cannot transfer tokens from the solver's account
/// to the recipient without requiring the solver to first approve the contract (via approve)
/// and then the contract calling transferFrom. This requires two transactions and adds complexity.
/// Instead, the solver must call transfer(to, amount) directly from their account. Since the
/// standard ERC20 transfer() function only accepts (address, uint256) parameters, we cannot
/// add intent_id as a parameter. We therefore append intent_id as extra calldata after the
/// function parameters. The ERC20 contract ignores these extra bytes (they don't match any
/// function signature), but they remain in the transaction data for verifier tracking. This
/// is different from Aptos, where we can create a custom contract function that transfers
/// tokens from A to B in one call and includes intent_id as an explicit parameter.
fn generate_evm_template(args: &Args) -> Result<()> {
    // Strip 0x prefix from addresses for hex formatting
    let recipient_clean = strip_0x(&args.recipient)?;
    let intent_clean = strip_0x(&args.intent_id)?;

    // Parse amount as U256 for EVM (supports large numbers)
    let amount_u256 = U256::from_dec_str(&args.amount)
        .with_context(|| format!("--amount '{}' is not a valid decimal number", args.amount))?;

    // ERC20 transfer function selector: transfer(address,uint256) = 0xa9059cbb
    let selector = "a9059cbb";

    // Format addresses and amounts as 32-byte hex strings (64 hex chars, right-padded)
    let recipient_hex = format!("{:0>64}", recipient_clean.to_lowercase());
    let amount_hex = format!("{amount:064x}", amount = amount_u256);
    let intent_hex = format!("{:0>64}", intent_clean.to_lowercase());

    // Concatenate: selector + to + amount + intent_id
    let data = format!(
        "0x{}{}{}{}",
        selector, recipient_hex, amount_hex, intent_hex
    );

    println!("=== Connected EVM Chain : Outflow fulfill transaction ===\n");
    println!("Recipient: 0x{}", recipient_clean);
    println!("Amount   : {} (base units)", args.amount);
    println!("Intent ID: 0x{}", intent_clean);
    println!("\n{}", "- ".repeat(30));
    println!("Call the ERC20 transfer() function with intent_id in calldata:");
    println!();
    println!("  cast send <token_address> --data {}", data);
    println!(
        "\n  Replace <token_address> with the ERC20 token contract address on the connected chain"
    );
    println!("\n  The transaction will:");
    println!("  - Transfer tokens from your account to the recipient address");
    println!("  - Include intent_id in the transaction calldata for verifier tracking\n");

    Ok(())
}

/// Normalizes an address to lowercase hex with 0x prefix.
///
/// Strips existing 0x prefix, validates hex characters, then adds 0x prefix back.
fn normalize_address(input: &str) -> Result<String> {
    let stripped = strip_0x(input)?;
    Ok(format!("0x{}", stripped.to_lowercase()))
}

/// Strips 0x prefix from a hex string and validates it contains only hex characters.
///
/// Returns the hex string without prefix, or an error if the string is empty or contains
/// non-hex characters.
fn strip_0x(input: &str) -> Result<String> {
    let s = input.trim();
    let without = s.strip_prefix("0x").unwrap_or(s);

    if without.is_empty() {
        anyhow::bail!("Address '{}' is empty", input);
    }

    if !without.chars().all(|c| c.is_ascii_hexdigit()) {
        anyhow::bail!("Address '{}' must be hex", input);
    }

    Ok(without.to_string())
}
