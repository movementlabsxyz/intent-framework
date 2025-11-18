# Testing Infrastructure

Infrastructure setup for running chains for development and testing.

## Resources

- [Testing Guide](./testing-guide.md) - Testing and validation commands

## Verifier API

- API: `http://127.0.0.1:3333`
- Port: 3333 (configurable in `trusted-verifier/config/verifier_testing.toml`)

## E2E Tests

- **[Move VM E2E Tests](./e2e-tests-mvm/README.md)** - Tests Move VM-only cross-chain intents (Chain 1 → Chain 2)
- **[EVM E2E Tests](./e2e-tests-evm/README.md)** - Tests mixed-chain intents (Move VM Chain 1 → EVM Chain 3)
