# Intent Framework

A framework for creating conditional trading intents with the following components

- [move-intent-framework](docs/move-intent-framework/README.md)
- [evm-intent-framework](docs/evm-intent-framework/README.md)
- [trusted verifier](docs/trusted-verifier/README.md)
- [solver tools](docs/solver/README.md)
- [testing infrastructure](docs/testing-infra/README.md)

For complete documentation, see [docs/](docs/README.md).

For contributing guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Quick start

- Enter dev shell with pinned toolchain (Rust, Movement CLI, Aptos CLI):

```text
nix develop
```

### Testing

#### Unit Tests (no Docker required)

Run from project root:

```bash
nix develop -c bash -c "cd move-intent-framework && movement move test --dev --named-addresses mvmt_intent=0x123"
RUST_LOG=off nix develop -c bash -c "cd trusted-verifier && cargo test --quiet"
nix develop -c bash -c "cd evm-intent-framework && npm test"
RUST_LOG=off nix develop -c bash -c "cd solver && cargo test --quiet"
```

#### E2E Integration Tests (requires Docker)

Run from project root:

```bash
nix develop -c bash -c "./testing-infra/ci-e2e/e2e-tests-mvm/run-tests-inflow.sh"
nix develop -c bash -c "./testing-infra/ci-e2e/e2e-tests-mvm/run-tests-outflow.sh"
nix develop -c bash -c "./testing-infra/ci-e2e/e2e-tests-evm/run-tests-inflow.sh"
```

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
