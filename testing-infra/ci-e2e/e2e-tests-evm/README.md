# EVM E2E Tests

Tests mixed-chain intent framework: intents on Move VM Chain 1 (hub) and escrows on EVM Chain 3.

## Quick Start

```bash
# Inflow tests (Connected EVM Chain → Hub)
./testing-infra/ci-e2e/e2e-tests-evm/run-tests-inflow.sh

# Outflow tests (Hub → Connected EVM Chain)
./testing-infra/ci-e2e/e2e-tests-evm/run-tests-outflow.sh
```

> **Note**: These E2E tests only run on Linux (for CI). They do not work on macOS because Docker images for the test chains are not available for macOS.

## What's Tested

1. **Verifier-Based Negotiation**: Draft submission, solver polling, and signature retrieval
2. **Intent Creation**: Creates intent on Move VM Chain 1 with solver signature from verifier
3. **Escrow Creation**: Creates escrow on EVM Chain 3 with locked tokens
4. **Intent Fulfillment**: Solver fulfills intent on Chain 1
5. **Verifier Approval**: Verifier monitors and generates ECDSA approval signature
6. **Escrow Release**: Escrow released on EVM Chain 3 with verifier signature
