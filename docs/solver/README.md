# Solver Tools

Tools for solvers to interact with the Intent Framework, including signature generation for reserved intents. Solvers fulfill intents by providing desired tokens or assets. For reserved intents, solvers must sign an `IntentToSign` structure off-chain.

## Quick Start

See the [component README](../../solver/README.md) for quick start commands.

## Overview

Command-line utilities for:

1. **Generate Signatures**: Sign `IntentToSign` structures for reserved intents
2. **Build Transaction Templates**: Generate Move VM/EVM payload templates with embedded `intent_id` for outflow fulfillment

## Architecture

Solvers interact through off-chain negotiation: creator creates draft → solver signs intent → creator submits on-chain.

Components:

- Signature Generator: Creates Ed25519 signatures for `IntentToSign` structures
- Transaction Template Generator: Produces Move/EVM templates with embedded `intent_id`
- Key Management: Reads solver private keys from Aptos configuration

## Project Structure

```
solver/
├── src/bin/        # Utility binaries (sign_intent, connected_chain_tx_template)
└── Cargo.toml
```

## Reserved Intents

Reserved intents require off-chain negotiation:

1. Creator creates a draft intent (off-chain)
2. Solver signs the `IntentToSign` structure (off-chain)
3. Creator submits the intent on-chain with the solver's signature

This ensures only the authorized solver can fulfill the intent, providing commitment guarantees for cross-chain scenarios.

Signature generation process:

1. Calls `utils::get_intent_to_sign_hash()` to construct and hash the `IntentToSign` structure
2. Extracts the hash from the transaction event
3. Reads the solver's private key from Aptos config
4. Signs the hash with Ed25519
5. Outputs signature (hex with `0x` prefix) to stdout
6. Outputs public key (hex with `0x` prefix) to stderr with `PUBLIC_KEY:` prefix

**Note**: For accounts created with `aptos init` (new authentication key format), the public key must be passed explicitly to the Move contract. The script extracts the public key from stderr output.

### Usage Example

Generate a signature for an intent:

```bash
cargo run --bin sign_intent -- \
  --profile solver-chain1 \
  --chain-address 0x123 \
  --offered-metadata 0xabc \
  --offered-amount 100000000 \
  --offered-chain-id 1 \
  --desired-metadata 0xdef \
  --desired-amount 100000000 \
  --desired-chain-id 2 \
  --expiry-time 1234567890 \
  --issuer 0xrequester \
  --solver 0xsolver \
  --chain-num 1
```

For more details on the reserved intent flow, see [Protocol Documentation](../protocol.md).

## Connected Chain Outflow Fulfillment Transaction Templates

Outflow intents require solvers to execute a transfer on the connected chain with the hub `intent_id` encoded. The `connected_chain_tx_template` binary produces templates for Move VM and EVM transfers.

**Move VM:**
```bash
cargo run --bin connected_chain_tx_template -- \
  --chain mvm \
  --recipient <address> \
  --metadata <metadata_address> \
  --amount <amount> \
  --intent-id <intent_id>
```

**EVM:**

```bash
cargo run --bin connected_chain_tx_template -- \
  --chain evm \
  --recipient <address> \
  --amount <amount> \
  --intent-id <intent_id>
```

The binary prints parameters that must match the hub intent and the command/calldata to execute the transfer.

**Note:** For Move VM, `--metadata` must be a hex address (object address of Metadata), not a module path. The intent framework module must be deployed on the connected chain.
