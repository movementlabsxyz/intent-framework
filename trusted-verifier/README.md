# Trusted Verifier Service

## WARNING: The current event discovery approach is NOT final!**

### Current Issue
The verifier currently uses a **known accounts approach** to discover events:
- Polls only configured test accounts (Alice, Bob) defined in `config/verifier.toml`
- Extracts events from user transaction history (`/v1/accounts/{address}/transactions`)
- This approach **will miss events** from any account not explicitly configured

### Why This Is Problematic
1. **Incomplete coverage**: Only monitors specific known accounts, missing events from all other users
2. **Manual configuration**: Requires knowing all event-emitting accounts in advance
3. **Not scalable**: Cannot handle production use cases with many users

### Required Fixes for Production

The following approaches should be implemented:

1. **Aptos Indexer GraphQL API** (RECOMMENDED)
   - Query events by event type across ALL accounts
   - Most efficient and scalable solution
   - Requires deploying/using an Aptos Indexer
   - See: https://aptos.guide/network/blockchain/events

2. **EventHandle with Global Resource** (Alternative)
   - Use deprecated EventHandle pattern with a global resource at a known address
   - Would allow querying via `/v1/accounts/{address}/events/{creation_number}`
   - However, Aptos has deprecated EventHandle in favor of module events
   - Reference: https://aptos.guide/network/blockchain/events

3. **Block/Transaction Scanning** (Not Recommended)
   - Scan all blocks/transactions for specific event types
   - Very inefficient and resource-intensive
   - Only suitable for low-throughput testnets

### Current Workaround
For testing purposes, the verifier can monitor known test accounts. **DO NOT USE IN PRODUCTION** without implementing proper event discovery.

---

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
