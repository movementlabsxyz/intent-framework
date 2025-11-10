# Trusted Verifier Service

A trusted verifier service that monitors escrow deposit events and triggers actions on other chains or systems.

Currently this handles a very simple case - transfers from a connected chain to the hub.

The trusted verifier is an external service that:

1. Monitors intent events on the hub chain for new intents
2. Monitors escrow events from escrow systems
3. Validates fulfillment of intent (deposit conditions) on the connected chain
4. Provides approval/rejection confirmation for intent fulfillment
5. Provides approval/rejection for escrow completion

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

- **Event Monitor**: Listens for escrow deposit events
- **Cross-chain Validator**: Validates conditions on connected chain
- **Action Trigger**: Triggers actions based on validation results (both on hub and connected chain)
- **Approval Service**: Provides approval/rejection signatures (both on hub and connected chain)

### Project Structure

```
trusted-verifier/
├── README.md                    # This overview
├── Cargo.toml                   # Rust project configuration
├── .gitignore                   # Git ignore rules
├── config/                      # Configuration files
│   └── verifier.template.toml  # Configuration template (copy to verifier.toml)
└── src/                        # Source code modules
    ├── main.rs                 # Application entry point and initialization
    ├── config/mod.rs           # Configuration management with TOML support
    ├── monitor/mod.rs          # Event monitoring for hub and connected chains
    ├── validator/mod.rs        # Cross-chain validation logic
    ├── crypto/mod.rs           # Ed25519 cryptographic operations
    ├── api/mod.rs              # REST API server with warp framework
    └── bin/                    # Utility binaries
        └── generate_keys.rs   # Key generation utility for Ed25519 key pairs
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

**Aptos Integration**: This project uses a pinned version of `aptos-core` for stable Rust compatibility:
- **Pinned to**: `aptos-framework-v1.37.0` (SHA: `a10a3c02f16a2114ad065db6b4a525f0382e96a6`)
