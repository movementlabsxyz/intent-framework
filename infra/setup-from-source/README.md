# Manual Aptos Chain Setup (From Source)

This directory contains scripts and configurations for setting up Aptos chains manually from source code, including support for multiple chains (Chain A and Chain B).

> ⚠️ **IMPORTANT WARNING**: The manual setup does **NOT** work for multi-chain configurations due to port conflicts and CLI limitations. Use Docker setup for multi-chain development.

## Overview

This setup provides:
- **Single Validator Setup** - Basic local development environment
- **Manual Control** - Full control over configuration and deployment
- **Source-based** - Builds and runs Aptos from source code

## Quick Start

### Build Aptos from Source (Required First)

```bash
# Build Movement's aptos-core fork
./infra/setup-from-source/build_aptos_from_source.sh
```

**Build Output**: Binaries are created in `infra/external/aptos-core/target/release/`:
- `aptos-node` - Main Aptos node binary
- `aptos-faucet-service` - Faucet service binary

### Multi-Chain Setup (Advanced)

```bash
# Setup Chain A (requires build step first)
./infra/setup-from-source/setup-chain-a.sh

# Setup Chain B  
./infra/setup-from-source/setup-chain-b.sh

# Test Chain A
./infra/setup-from-source/test-chain-a.sh
```

## Directory Structure

```
infra/setup-from-source/
├── build_aptos_from_source.sh  # Build Movement's aptos-core fork
├── setup-chain-a.sh            # Chain A setup script
├── setup-chain-b.sh            # Chain B setup script
├── test-chain-a.sh             # Chain A testing script
├── setup-guide.md              # Detailed setup instructions
└── config/                     # Configuration files and templates
    ├── validator_node.yaml     # Validator configuration template
    └── data/                   # Validator data directory
```

## What's Included

- **Single Validator**: Complete local Aptos node with faucet
- **Configuration Files**: YAML configs for different setups
- **Test Scripts**: Automated testing and validation

## Benefits

- ✅ **Full Control** - Complete control over configuration
- ✅ **Source-based** - Builds from Aptos source code
- ✅ **Customizable** - Easy to modify configurations
- ✅ **Production-like** - Closer to production setup

## When to Use

- **Development**: When you need full control over the setup
- **Custom Configurations**: When you need specific node configurations
- **Production Simulation**: When you need a setup closer to production

## Prerequisites

- Rust toolchain installed
- Aptos CLI installed
- Sufficient system resources
- Network configuration knowledge

### System Dependencies

Install required system packages:

```bash
# Install system dependencies
sudo apt install -y $(cat infra/setup-from-source/requirements.txt)
```

## Known Limitations

- **Port Configuration**: `aptos node run-localnet` doesn't support custom ports (hardcoded to 8080/8081)
- **CLI Funding Issues**: `aptos init` may hang during account funding
- **Multi-chain Complexity**: Requires manual configuration for parallel chains
- **Troubleshooting**: May require manual intervention for persistent issues

See the [setup guide](./setup-guide.md) for detailed troubleshooting steps.

## Next Steps

1. Choose your setup type (single validator or multi-chain)
2. Follow the detailed [setup guide](./setup-guide.md) for step-by-step instructions
3. Configure your development environment
4. Start developing with your custom Aptos setup

For Docker-based setup (easier), see [../setup-docker/README](../setup-docker/README.md).

## Testing and Validation

For common testing commands and validation steps that work with both Docker and manual setups, see the [shared testing guide](../testing-guide.md).
