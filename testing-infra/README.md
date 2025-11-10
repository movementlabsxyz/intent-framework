# Testing Infrastructure

Infrastructure setup for running chains for development and testing.

📚 **Full documentation: [docs/testing-infra/](../docs/testing-infra/README.md)**

## Quick Start

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

- Chain 1: REST `http://127.0.0.1:8080` • Faucet `http://127.0.0.1:8081`
- Chain 2: REST `http://127.0.0.1:8082` • Faucet `http://127.0.0.1:8083`

### EVM Chain (Hardhat)

```bash
# Start EVM chain
./testing-infra/chain-connected-evm/setup-chain.sh

# Stop EVM chain
./testing-infra/chain-connected-evm/stop-chain.sh
```

**Endpoints:**

- EVM Chain: RPC `http://127.0.0.1:8545`, Chain ID: 31337

### E2E Tests

- **[Aptos E2E Tests](./e2e-tests-apt/README.md)** - Tests Aptos-only cross-chain intents (Chain 1 → Chain 2)
- **[EVM E2E Tests](./e2e-tests-evm/README.md)** - Tests mixed-chain intents (Aptos Chain 1 → EVM Chain 3)
