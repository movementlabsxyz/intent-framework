# EVM E2E Tests

Tests mixed-chain intent framework: intents on Move VM Chain 1 (hub) and escrows on EVM Chain 3.

## Quick Start

```bash
./testing-infra/e2e-tests-evm/run-tests.sh
```

## What's Tested

1. **Intent Creation**: Creates intent on Move VM Chain 1 requesting APT
2. **Escrow Creation**: Creates escrow on EVM Chain 3 with locked ETH (1000 ETH for 1 APT)
3. **Intent Fulfillment**: Bob fulfills intent on Chain 1
4. **Verifier Approval**: Verifier monitors and generates ECDSA approval signature
5. **Escrow Release**: Escrow released on EVM Chain 3 with verifier signature
