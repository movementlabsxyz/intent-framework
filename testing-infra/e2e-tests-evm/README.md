# EVM E2E Tests

End-to-end testing infrastructure for EVM intent vault.

## Overview

This directory contains scripts to set up and test the EVM intent vault on a local Hardhat node.

## Quick Start

```bash
# Run all E2E tests (starts chain, deploys, tests, cleans up)
./testing-infra/e2e-tests-evm/run-tests.sh
```

## Manual Setup

```bash
# Start EVM chain
./testing-infra/connected-chain-evm/setup-evm-chain.sh

# Deploy vault contract
./testing-infra/e2e-tests-evm/deploy-vault.sh

# Run tests manually
cd evm-intent-framework
npx hardhat test --network localhost

# Stop chain when done
./testing-infra/connected-chain-evm/stop-evm-chain.sh
```

## Components

### `setup-evm-chain.sh`
- Starts Hardhat node on port 8545
- Waits for node to be ready
- Uses Hardhat default accounts (20 accounts, each with 10000 ETH)
- Fresh start each time (no state persistence)

### `deploy-vault.sh`
- Deploys IntentVault contract to localhost
- Sets verifier address to second Hardhat account
- Outputs contract address for use in tests

### `run-tests.sh`
- Complete test runner:
  1. Starts EVM chain
  2. Deploys contract
  3. Runs tests
  4. Cleans up

### `stop-evm-chain.sh`
- Stops Hardhat node
- Cleans up PID files

## Configuration

- **RPC URL**: http://127.0.0.1:8545
- **Chain ID**: 31337 (Hardhat default)
- **Network**: localhost

## Hardhat Default Accounts

Hardhat provides 20 test accounts, each with 10000 ETH:

- Account 0: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- Account 1: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`
- Account 2: `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`
- ... (see Hardhat docs for full list)

Private keys are deterministic from the mnemonic: `test test test test test test test test test test test junk`

## Differences from Aptos Setup

- **No Docker**: Uses Hardhat's built-in node directly
- **No Faucet**: Accounts are pre-funded
- **Simpler**: Single node vs dual chains
- **Faster**: Hardhat node starts in seconds vs minutes for Aptos

