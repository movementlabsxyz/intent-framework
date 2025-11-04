# Intent Framework

A framework for creating conditional trading intents with the following components

- [move-intent-framework](move-intent-framework/README.md)
- [evm-intent-framework](evm-intent-framework/README.md)
- [trusted verifier](trusted-verifier/docs/README.md)

## Quick start

- Enter dev shell with pinned toolchain (Rust, Aptos CLI):

```
nix develop
```

### Testing

#### Unit Tests (no Docker required)

Run from project root:

```bash
nix develop -c bash -c "cd move-intent-framework && aptos move test --dev --named-addresses aptos_intent=0x123"
nix develop -c bash -c "cd trusted-verifier && cargo test"
nix develop -c bash -c "cd evm-intent-framework && npm test"
```

#### E2E Integration Tests (requires Docker)

Run from project root:

```bash
nix develop -c bash -c "./testing-infra/e2e-tests-apt/run-tests.sh"
nix develop -c bash -c "./testing-infra/e2e-tests-evm/run-tests.sh"
```

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
