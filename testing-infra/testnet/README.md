# Testnet Deployment Infrastructure

This directory contains scripts and configuration for deploying the Intent Framework to public testnets (Movement Bardock Testnet and Base Sepolia).

**Note**: This is separate from `testing-infra/ci-e2e/` which is for local CI testing with Docker-based chains.

## Files

- **`deploy-movement-testnet.sh`** - Deploy Move Intent Framework to Movement Bardock Testnet
- **`deploy-base-testnet.sh`** - Deploy EVM IntentEscrow to Base Sepolia Testnet
- **`check-testnet-balances.sh`** - Check balances for all testnet accounts
- **`config/testnet-assets.toml`** - Public configuration for asset addresses and decimals

## Usage

### Deploy to Movement Bardock Testnet

```bash
./testing-infra/testnet/deploy-movement-testnet.sh
```

### Deploy to Base Sepolia Testnet

```bash
./testing-infra/testnet/deploy-base-testnet.sh
```

### Check Testnet Balances

```bash
./testing-infra/testnet/check-testnet-balances.sh
```

## Configuration

All scripts read from:
- `.testnet-keys.env` - Private keys and addresses (gitignored)
- `config/testnet-assets.toml` - Public asset addresses and decimals

See `.taskmaster/tasks/TESTNET_DEPLOYMENT_PLAN.md` for detailed deployment instructions.

