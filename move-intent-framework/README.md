# Move Intent Framework

Aptos Move contracts for intents and escrows.

📚 **Full documentation: [docs/move-intent-framework/](../docs/move-intent-framework/README.md)**

## Quick Start

### Prerequisites

- [Nix](https://nixos.org/download.html) package manager
- CLI tools (automatically provided via [aptos.nix](../aptos.nix))

### Run Tests

```bash
# From project root
nix develop -c bash -c "cd move-intent-framework && aptos move test --dev --named-addresses mvmt_intent=0x123"
```

### Development Environment

```bash
# From project root
nix develop
```
