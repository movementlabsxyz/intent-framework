# Intent Framework

A framework for creating conditional trading intents with the following components

- [move-intent-framework README](move-intent-framework/README.md)
- [trusted verifier](trusted-verifier/docs/README.md)

## Quick start

- Enter dev shell with pinned toolchain (Rust, Aptos CLI):

```
nix develop
```

### Testing

```
cd move-intent-framework && aptos move test --dev --named-addresses aptos_intent=0x123 && cd ..

# the following test is also required for the trusted-verifier integration test
./trusted-verifier/tests/integration/run-cross-chain-verifier.sh 1

cd trusted-verifier && cargo test --locked && cd ..
```

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
