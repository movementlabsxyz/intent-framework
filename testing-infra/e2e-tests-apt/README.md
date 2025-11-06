# Aptos E2E Tests

Tests Aptos-only cross-chain intent framework: intents on Chain 1 (hub) and escrows on Chain 2 (connected).

## Quick Start

```bash
./testing-infra/e2e-tests-apt/run-tests.sh
```

## What's Tested

1. **Intent Creation**: Creates intent on Chain 1 requesting tokens
2. **Escrow Creation**: Creates escrow on Chain 2 with locked tokens
3. **Intent Fulfillment**: Bob fulfills intent on Chain 1
4. **Verifier Approval**: Verifier monitors and generates Ed25519 approval signature
5. **Escrow Release**: Escrow released on Chain 2 with verifier signature

## Integration Tests

The `verifier-rust-integration-tests/` directory contains Rust integration tests for the trusted verifier library (connectivity, deployment, event polling). These are automatically run by `run-tests.sh`.
