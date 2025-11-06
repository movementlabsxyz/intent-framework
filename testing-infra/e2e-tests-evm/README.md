# EVM E2E Tests

Tests mixed-chain intent framework: intents on Aptos Chain 1 (hub) and escrows on EVM Chain 3.

## Quick Start

```bash
python3 testing-infra/e2e-tests-evm/run_tests.py
```

## What's Tested

1. **Intent Creation**: Creates intent on Aptos Chain 1 requesting APT
2. **Escrow Creation**: Creates escrow on EVM Chain 3 with locked ETH (1000 ETH for 1 APT)
3. **Intent Fulfillment**: Bob fulfills intent on Chain 1
4. **Verifier Approval**: Verifier monitors and generates ECDSA approval signature
5. **Escrow Release**: Escrow released on EVM Chain 3 with verifier signature

## Test Scripts

- `run_tests.py` - Complete test runner (setup → test → cleanup)
- `setup_and_deploy_evm.py` - Sets up EVM chain and deploys vault
- `deploy_vault.py` - Deploys IntentVault contract to EVM
- `submit_cross_chain_intent_evm.py` - Creates intent and escrow
- `release_evm_escrow.py` - Runs verifier and releases escrow
