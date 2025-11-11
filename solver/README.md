# Solver Tools

Tools for solvers to interact with the Intent Framework, including signature generation for reserved intents.

📚 **Full documentation: [docs/solver/](../docs/solver/README.md)**

## Quick Start

### Build

```bash
cargo build
```

### Usage

Generate a signature for an intent:

```bash
cargo run --bin sign_intent -- \
  --profile bob-chain1 \
  --chain-address 0x123 \
  --source-metadata 0xabc \
  --desired-metadata 0xdef \
  --desired-amount 100000000 \
  --expiry-time 1234567890 \
  --issuer 0xalice \
  --solver 0xbob \
  --chain-num 1
```

### Development Commands

```bash
# Run tests (when available)
cargo test

# Format code
cargo fmt

# Check code
cargo clippy
```
