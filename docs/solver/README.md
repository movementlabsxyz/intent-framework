# Solver Tools

Tools for solvers to interact with the Intent Framework, including signature generation for reserved intents.

Solvers are parties that fulfill intents by providing the desired tokens or assets. For reserved intents, solvers must sign an `IntentToSign` structure off-chain to commit to fulfilling the intent.

## Quick Start

For quick start instructions, see the [component README](../../solver/README.md).

## Overview

The solver tools provide command-line utilities for solvers to:

1. **Generate Signatures**: Sign `IntentToSign` structures to commit to fulfilling reserved intents
2. **Intent Management**: (Future) Tools for monitoring and managing intent fulfillment

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
- **Key Management**: Reads solver private keys from Aptos configuration
- **Hash Extraction**: Retrieves intent hashes from on-chain events

### Project Structure

```
solver/
├── README.md                    # Component overview and usage
├── Cargo.toml                   # Rust project configuration
└── src/
    └── bin/                     # Utility binaries
        └── sign_intent.rs       # Intent signature generation utility
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

For more details on the reserved intent flow, see [Protocol Documentation](../protocol.md).
