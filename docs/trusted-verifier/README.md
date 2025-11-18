# Trusted Verifier Service

A trusted verifier service that monitors escrow deposit events and triggers actions on other chains or systems.

Currently this handles a very simple case - transfers from a connected chain to the hub.

The trusted verifier is an external service that:

1. Monitors intent events on the hub chain for new intents
2. Monitors escrow events from escrow systems on connected chains (both Move VM and EVM)
3. Validates fulfillment of intent (deposit conditions) on the connected chain
4. Generates approval signatures for escrow completion (signature itself is the approval)

The verifier supports monitoring multiple connected chains simultaneously:

- **Move VM connected chains**: Monitors `OracleLimitOrderEvent` events for escrow creation
- **EVM connected chains**: Monitors `EscrowInitialized` events for escrow creation
Both chain types are monitored symmetrically - escrows are cached and validated when created, not retroactively.

## Architecture

```text
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Chain 1         │    │ Trusted Verifier │    │ Chain 2         │
│ (Hub)           │    │                  │    │ (Connected)     │
│                 │    │                  │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │ Intent      │ │◄───┤ │ Event Monitor│ │    │ │ Escrow      │ │
│ │ Framework   │ │    │ │              │ │───►│ │             │ │
│ │             │ │    │ │ Cross-chain  │ │    │ │             │ │
│ │             │ │    │ │ Validator    │ │    │ │             │ │
│ └─────────────┘ │    │ └──────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Components

- **Event Monitor**: Listens for escrow deposit events on both Move VM and EVM connected chains
- **Cross-chain Validator**: Validates conditions on connected chains (supports both Move VM and EVM)
- **Action Trigger**: Triggers actions based on validation results (both on hub and connected chain)
- **Approval Service**: Provides approval signatures by signing the `intent_id` (Ed25519 for Move VM, ECDSA for EVM). The signature itself is the approval.

### Project Structure

```text
trusted-verifier/
├── README.md                    # This overview
├── Cargo.toml                   # Rust project configuration
├── .gitignore                   # Git ignore rules
├── config/                      # Configuration files
│   └── verifier.template.toml  # Configuration template (copy to verifier.toml)
└── src/                        # Source code modules
    ├── main.rs                 # Application entry point and initialization
    ├── config/mod.rs           # Configuration management with TOML support
    ├── monitor/                # Event monitoring for hub and connected chains
    │   ├── mod.rs              # Module declarations and re-exports
    │   ├── generic.rs          # Shared event structures and EventMonitor implementation
    │   ├── inflow_generic.rs  # Chain-agnostic inflow monitoring and validation
    │   ├── outflow_generic.rs # Chain-agnostic outflow monitoring
    │   ├── inflow_mvm.rs       # Move VM-specific escrow event polling for connected chains
    │   ├── inflow_evm.rs       # EVM-specific escrow event polling for connected chains
    │   ├── outflow_mvm.rs       # Move VM-specific hub chain request intent event polling
    │   └── outflow_evm.rs      # EVM-specific hub chain monitoring (reserved for future)
    ├── validator/               # Cross-chain validation logic
    │   ├── mod.rs              # Module declarations and re-exports
    │   ├── generic.rs          # Shared structures and CrossChainValidator implementation
    │   ├── inflow_generic.rs   # Chain-agnostic inflow validation logic
    │   ├── outflow_generic.rs  # Chain-agnostic outflow validation logic
    │   ├── inflow_mvm.rs       # Move VM-specific inflow validation (reserved for future)
    │   ├── inflow_evm.rs       # EVM-specific inflow validation (escrow solver validation)
    │   ├── outflow_mvm.rs      # Move VM-specific outflow transaction parameter extraction
    │   └── outflow_evm.rs      # EVM-specific outflow transaction parameter extraction
    ├── crypto/mod.rs           # Cryptographic operations (Ed25519 for Move VM, ECDSA for EVM)
    ├── mvm_client.rs          # Move VM blockchain client for event querying
    ├── evm_client.rs          # EVM blockchain client for event querying
    ├── api/                    # REST API server with warp framework
    │   ├── mod.rs              # Module declarations and re-exports
    │   ├── generic.rs          # Shared API structures and ApiServer implementation
    │   ├── inflow_generic.rs   # Chain-agnostic inflow escrow validation handlers
    │   ├── outflow_generic.rs  # Chain-agnostic outflow fulfillment validation handlers
    │   ├── inflow_mvm.rs       # Move VM-specific inflow handlers (reserved for future)
    │   ├── inflow_evm.rs       # EVM-specific inflow handlers (reserved for future)
    │   ├── outflow_mvm.rs      # Move VM-specific outflow transaction querying
    │   └── outflow_evm.rs      # EVM-specific outflow transaction querying
    └── bin/                    # Utility binaries
        ├── generate_keys.rs   # Key generation utility for Ed25519 key pairs
        └── get_verifier_eth_address.rs  # Derive Ethereum address from Ed25519 key
```

## Quick Start

For quick start instructions, see the [component README](../../trusted-verifier/README.md).

## API Endpoints

- `GET /health` - Health check
- `GET /events` - Get cached intent events
- `POST /approval` - Create approval signature
- `GET /public-key` - Get verifier public key

For detailed API documentation, see [api.md](api.md). For usage guide, see [guide.md](guide.md).

## Dependencies

**Move VM Integration**: This project uses a pinned version of `aptos-core` for stable Rust compatibility:

- **Pinned to**: `aptos-framework-v1.37.0` (SHA: `a10a3c02f16a2114ad065db6b4a525f0382e96a6`)
