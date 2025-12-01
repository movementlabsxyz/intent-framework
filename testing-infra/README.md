# Testing Infrastructure

Infrastructure for development testing and testnet deployment.

## Directory Structure

```text
testing-infra/
├── ci-e2e/          # Local CI/E2E testing (Docker-based)
│   ├── chain-hub/           # Hub chain setup (Chain 1)
│   ├── chain-connected-mvm/ # Connected MVM chain (Chain 2)
│   ├── chain-connected-evm/ # Connected EVM chain (Chain 3)
│   ├── e2e-tests-mvm/       # MVM-only cross-chain tests
│   ├── e2e-tests-evm/       # Mixed MVM/EVM cross-chain tests
│   ├── test-tokens/         # Test token contracts
│   └── util*.sh             # Shared utilities
└── testnet/         # Public testnet deployment
    ├── config/              # Testnet asset configuration
    └── check-testnet-balances.sh
```

## CI/E2E Tests

Local testing using Docker containers:

- **[Move VM E2E Tests](./ci-e2e/e2e-tests-mvm/README.md)** - MVM-only cross-chain intents (Chain 1 → Chain 2)
- **[EVM E2E Tests](./ci-e2e/e2e-tests-evm/README.md)** - Mixed-chain intents (MVM Chain 1 → EVM Chain 3)

📚 **Full documentation: [docs/testing-infra/](../docs/testing-infra/README.md)**

## Testnet

Scripts for deploying to and interacting with public testnets (Movement Bardock, Base Sepolia).
