# Trusted Verifier Service

Service that monitors chains and provides approval signatures.

📚 **Full documentation: [docs/trusted-verifier/](../docs/trusted-verifier/README.md)**

## Quick Start

### Build

```bash
cargo build
```

### Configure

```bash
# Copy the template and edit with your chain URLs and keys
cp config/verifier.template.toml config/verifier.toml

# Generate cryptographic keys (optional)
cargo run --bin generate_keys

# Edit config/verifier.toml with your actual values
```

### Run

```bash
cargo run
```

### Development Commands

```bash
# Run tests
cargo test

# Run with logging
RUST_LOG=debug cargo run

# Generate Ed25519 key pairs
cargo run --bin generate_keys

# Format code
cargo fmt

# Check code
cargo clippy
```
