# Trusted Verifier Service

⚠️ **NOTE**: Initially this handles a very simple case - transfers from a connected chain to the hub!

A trusted verifier service that monitors escrow deposit events and triggers actions on other chains or systems.

## Dependencies

**Aptos Integration**: This project uses a pinned version of `aptos-core` for stable Rust compatibility:
- **Pinned to**: `aptos-framework-v1.37.0` (SHA: `a10a3c02f16a2114ad065db6b4a525f0382e96a6`)
- **Verification**: Run `./infra/external/verify-aptos-pin.sh` to ensure pin integrity
- **Updates**: Use `./infra/external/triage-aptos-pin.sh` to find compatible newer versions

## Overview

The trusted verifier is an external service that:

1. **Monitors intent events** on the hub chain for new intents
2. **Monitors escrow events** from escrow systems
3. **Validates fulfillment of intent** (deposit conditions) on the connected chain
4. **Provides approval/rejection confirmation for intent fulfillment**
5. **Provides approval/rejection for escrow completion**

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

## Security Requirements

⚠️ **CRITICAL**: The verifier must ensure that escrow intents are **non-revocable** (`revocable = false`) before triggering any actions elsewhere.

## Components

- **Event Monitor**: Listens for escrow deposit events
- **Cross-chain Validator**: Validates conditions on connected chain
- **Action Trigger**: Triggers actions based on validation results (both on hub and connected chain)
- **Approval Service**: Provides approval/rejection signatures (both on hub and connected chain)

## Rust Implementation

This service is implemented in Rust with comprehensive documentation and modular architecture.

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

### Service Capabilities

- **Monitor blockchain events** from both hub and connected chains
- **Validate conditions** on connected chain against hub chain intents
- **Trigger actions** on hub and connected chains based on validation
- **Provide cryptographic signatures** for approval/rejection decisions

## Integration

The verifier integrates with escrow systems by:

1. Monitoring `LimitOrderEvent` and `OracleLimitOrderEvent`
2. Validating deposit conditions
3. Providing approval signatures for escrow completion
4. Ensuring non-revocable escrow intents

### Quick Start

1. **Build the project**:

   ```bash
   cargo build
   ```

2. **Configure the service**:

   ```bash
   # Copy the template and edit with your chain URLs and keys
   cp config/verifier.template.toml config/verifier.toml
   
   # Generate cryptographic keys (optional)
   cargo run --bin generate_keys
   
   # Edit config/verifier.toml with your actual values
   ```

3. **Run the service**:

   ```bash
   cargo run
   ```

### API Endpoints

- `GET /health` - Health check
- `GET /events` - Get cached intent events
- `POST /approval` - Create approval signature
- `GET /public-key` - Get verifier public key

### Development Commands

```bash
# Run tests
cargo test

# Run with logging
RUST_LOG=debug cargo run

# Generate Ed25519 key pairs
cargo run --bin generate_keys

# Format code
cargo fmt

# Check code
cargo clippy
```
