# Testing Infrastructure

Infrastructure setup for running chains for development and testing.

## Resources

- [Testing Guide](./testing-guide.md) - Testing and validation commands

## Chain Setup

### Aptos Chains (Docker)

```bash
# Multi-chain setup (two independent localnets with Alice and Bob accounts)
./testing-infra/chain-connected-apt/setup-alice-bob.sh

# Or setup chains only
./testing-infra/chain-connected-apt/setup-chain.sh

# Stop both chains
./testing-infra/chain-connected-apt/stop-chain.sh
```

**Endpoints:**
- Chain 1: REST http://127.0.0.1:8080 • Faucet http://127.0.0.1:8081
- Chain 2: REST http://127.0.0.1:8082 • Faucet http://127.0.0.1:8083

### EVM Chain (Hardhat)

```bash
# Start EVM chain
./testing-infra/chain-connected-evm/setup-chain.sh

# Stop EVM chain
./testing-infra/chain-connected-evm/stop-chain.sh
```

**Endpoints:**
- EVM Chain: RPC http://127.0.0.1:8545, Chain ID: 31337

### Verifier API

- API: http://127.0.0.1:3333
- Port: 3333 (configurable in `trusted-verifier/config/verifier_testing.toml`)

## Test Accounts

### Aptos Chains

Both Chain 1 and Chain 2 use the same test accounts:
- **Alice**: Creates intents and escrows
- **Bob**: Fulfills intents and claims escrows
- Funded with 200,000,000 Octas (2 APT) each during setup

### EVM Chain

Hardhat provides 20 test accounts, each with 10000 ETH:
- Account 0 (Deployer/Verifier): `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- Account 1 (Alice): `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`
- Account 2 (Bob): `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`
- Private keys are deterministic from mnemonic: `test test test test test test test test test test test junk`

## E2E Tests

- **[Aptos E2E Tests](./e2e-tests-apt/README.md)** - Tests Aptos-only cross-chain intents (Chain 1 → Chain 2)
- **[EVM E2E Tests](./e2e-tests-evm/README.md)** - Tests mixed-chain intents (Aptos Chain 1 → EVM Chain 3)
