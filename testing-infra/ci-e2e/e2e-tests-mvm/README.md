# Move VM E2E Tests

Tests Move VM-only cross-chain intent framework: intents on Chain 1 (hub) and escrows on Chain 2 (connected).

## Quick Start

```bash
# Inflow tests (Connected Chain → Hub)
./testing-infra/ci-e2e/e2e-tests-mvm/run-tests-inflow.sh

# Outflow tests (Hub → Connected Chain)
./testing-infra/ci-e2e/e2e-tests-mvm/run-tests-outflow.sh
```

> **Note**: These E2E tests only run on Linux (for CI). They do not work on macOS because Docker images for the test chains are not available for macOS.

## What's Tested

1. **Verifier-Based Negotiation**: Draft submission, solver polling, and signature retrieval
2. **Intent Creation**: Creates intent on Chain 1 with solver signature from verifier
3. **Escrow Creation**: Creates escrow on Chain 2 with locked tokens
4. **Intent Fulfillment**: Solver fulfills intent on Chain 1
5. **Verifier Approval**: Verifier monitors and generates Ed25519 approval signature
6. **Escrow Release**: Escrow released on Chain 2 with verifier signature

## Integration Tests

The `verifier-rust-integration-tests/` directory contains Rust integration tests for the trusted verifier library (connectivity, deployment, event polling). These are automatically run by `run-tests-inflow.sh`.
