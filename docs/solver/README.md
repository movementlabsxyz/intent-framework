# Solver Tools

Tools for solvers to interact with the Intent Framework, including signature generation for reserved intents.

Solvers are parties that fulfill intents by providing the desired tokens or assets. For reserved intents, solvers must sign an `IntentToSign` structure off-chain to commit to fulfilling the intent.

## Quick Start

For quick start instructions, see the [component README](../../solver/README.md).

## Overview

The solver tools provide command-line utilities for solvers to:

1. **Generate Signatures**: Sign `IntentToSign` structures to commit to fulfilling reserved intents
2. **Build Connected-Chain Outflow Fulfillment Transactions**: Generate Move VM/EVM payload templates that embed `intent_id`
3. **Intent Management**: (Future) Tools for monitoring and managing intent fulfillment

## Architecture

Solvers interact with the Intent Framework through an off-chain negotiation process:

```text
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│   Creator   │         │   Solver    │         │   Chain     │
│             │         │             │         │             │
│ 1. Create   │────────►│             │         │             │
│    draft    │         │             │         │             │
│             │         │ 2. Sign     │         │             │
│             │◄────────│    intent   │         │             │
│             │         │             │         │             │
│ 3. Submit   │         │             │────────►│ 4. Intent   │
│    on-chain │─────────┼─────────────┼────────►│    created  │
└─────────────┘         └─────────────┘         └─────────────┘
```

### Components

- **Signature Generator**: Creates Ed25519 signatures for `IntentToSign` structures
- **Connected Chain Outflow Fulfillment Template Generator**: Produces Move/EVM transaction templates with embedded `intent_id` for outflow intent fulfillment
- **Key Management**: Reads solver private keys from Aptos configuration
- **Hash Extraction**: Retrieves intent hashes from on-chain events

### Project Structure

```text
solver/
├── README.md                    # Component overview and usage
├── Cargo.toml                   # Rust project configuration
└── src/
    └── bin/                     # Utility binaries
        ├── sign_intent.rs                 # Intent signature generation utility
        └── connected_chain_tx_template.rs # Connected-chain transfer template helper
```

## Reserved Intents

Reserved intents require off-chain negotiation between the intent creator and the solver:

1. **Draft Creation**: Creator creates a draft intent (off-chain)
2. **Solver Signing**: Solver signs the `IntentToSign` structure (off-chain)
3. **On-chain Creation**: Creator submits the intent on-chain with the solver's signature

This ensures that only the authorized solver can fulfill the intent, providing commitment guarantees for cross-chain scenarios.

The signature generation process:

1. Calls `utils::get_intent_to_sign_hash()` Move function to construct and hash the `IntentToSign` structure
2. Extracts the hash from the transaction event
3. Reads the solver's private key from Aptos config (`.aptos/config.yaml` in project root)
4. Signs the hash with Ed25519
5. Outputs the signature as a hex string (with `0x` prefix) to stdout
6. Outputs the public key as a hex string (with `0x` prefix) to stderr with `PUBLIC_KEY:` prefix

**Note**: For accounts created with `aptos init` (new authentication key format), the public key must be passed explicitly to the Move contract since it cannot be extracted from the authentication key. The script extracts the public key from stderr output.

### Usage Example

Generate a signature for an intent:

```bash
cargo run --bin sign_intent -- \
  --profile bob-chain1 \
  --chain-address 0x123 \
  --source-metadata 0xabc \
  --desired-metadata 0xdef \
  --desired-amount 100000000 \
  --expiry-time 1234567890 \
  --issuer 0xalice \
  --solver 0xbob \
  --chain-num 1
```

For more details on the reserved intent flow, see [Protocol Documentation](../protocol.md).

## Connected Chain Outflow Fulfillment Transaction Templates

Outflow intents require solvers to execute a transfer on the connected chain and encode the hub `intent_id` in that transaction. The `connected_chain_tx_template` binary produces canonical templates for both Move VM and EVM transfers:

**For Move VM:**

```bash
cargo run --bin connected_chain_tx_template -- \
  --chain mvm \
  --recipient 0xcafe1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef \
  --metadata 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef \
  --amount 25000000 \
  --intent-id 0x5678123456789012345678901234567890123456789012345678901234567890
```

**For EVM:**

```bash
cargo run --bin connected_chain_tx_template -- \
  --chain evm \
  --recipient 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb \
  --amount 1000000000000000000 \
  --intent-id 0x5678123456789012345678901234567890123456789012345678901234567890
```

**Note:** For Move VM, `--metadata` must be a hex address (the object address of the Metadata object), not a module path like `0x1::fungible_asset::AptosCoinMetadata`. You can get the metadata object address from the token's metadata object.

The binary prints:

- The parameters that must match the hub intent
- For Move VM: The `aptos move run` command to call the on-chain `utils::transfer_with_intent_id()` function directly. This function performs the transfer and includes `intent_id` in the transaction payload. No script compilation needed - just call the function with the provided arguments.
- For EVM: The ERC20 calldata blob that extends `transfer(to, amount)` with an extra 32-byte `intent_id` word. This value is supplied as `data` when calling the ERC20 contract so the verifier can read it via `eth_getTransactionByHash`.

**Note:** For Move VM, the intent framework module (including `utils::transfer_with_intent_id()`) must be deployed on the connected chain. Once deployed, solvers can call the function directly without needing to compile scripts.
