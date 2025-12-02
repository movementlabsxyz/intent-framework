# Trusted Verifier Service

A service that monitors escrow deposit events and provides approval signatures for cross-chain operations.

The verifier supports two cross-chain flows:

**Outflow (hub → connected chain):**

1. Monitors intent events on the hub chain (request-intent creation)
2. Validates fulfillment transactions on connected chains (Move VM and EVM)
3. Validates that transfer conditions match intent requirements
4. Generates approval signatures for intent fulfillment on hub chain

**Inflow (connected chain → hub):**

1. Monitors intent events on the hub chain (request-intent creation)
2. Monitors escrow events on connected chains (Move VM and EVM)
3. Monitors fulfillment events on the hub chain (when solver fulfills)
4. Validates that fulfillment matches escrow conditions
5. Generates approval signatures for escrow release on connected chain

Supports monitoring multiple connected chains simultaneously. Move VM chains monitor `OracleLimitOrderEvent` events; EVM chains monitor `EscrowInitialized` events. Intents and escrows are monitored on both hub and connected chains - escrows are cached and validated when created.

## Architecture

### Components

- **Event Monitor**: Listens for intent and escrow events on hub and connected chains (Move VM and EVM)
- **Cross-chain Validator**: Validates fulfillment conditions on hub and connected chains (Move VM and EVM)
- **Approval Service**: Provides approval signatures by signing the `intent_id` (Ed25519 for Move VM, ECDSA for EVM)

## Project Structure

```text
trusted-verifier/
├── config/          # Configuration files
├── src/
│   ├── monitor/     # Event monitoring (hub and connected chains)
│   ├── validator/   # Cross-chain validation logic
│   ├── crypto/      # Cryptographic operations
│   ├── api/         # REST API server
│   └── bin/         # Utility binaries
└── Cargo.toml
```

## Quick Start

See the [component README](../../trusted-verifier/README.md) for quick start commands.

## API Endpoints

### Core Endpoints

- `GET /health` - Health check
- `GET /events` - Get cached intent events
- `POST /approval` - Create approval signature
- `GET /public-key` - Get verifier public key
- `POST /validate-outflow-fulfillment` - Validate connected chain transaction for outflow intent
- `POST /validate-inflow-escrow` - Validate escrow for inflow intent

### Negotiation Routing Endpoints

- `POST /draft-intent` - Submit draft intent (open to any solver)
- `GET /draft-intent/:id` - Get draft intent status
- `GET /draft-intents/pending` - Get all pending drafts (for solvers to poll)
- `POST /draft-intent/:id/signature` - Submit signature for draft (FCFS)
- `GET /draft-intent/:id/signature` - Poll for signature (for requesters)

For detailed API documentation, see [api.md](api.md). For usage guide, see [guide.md](guide.md). For negotiation routing guide, see [negotiation-routing.md](negotiation-routing.md).

## Dependencies

Uses pinned `aptos-core` version for stable Rust compatibility: `aptos-framework-v1.37.0` (SHA: `a10a3c02f16a2114ad065db6b4a525f0382e96a6`)
