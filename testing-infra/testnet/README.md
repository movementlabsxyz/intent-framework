# Testnet Deployment Infrastructure

This directory contains scripts and configuration for deploying the Intent Framework to public testnets (Movement Bardock Testnet and Base Sepolia).

**Note**: This is separate from `testing-infra/ci-e2e/` which is for local CI testing with Docker-based chains.

## Files

### Deployment Scripts

- **`deploy-to-movement-testnet.sh`** - Deploy Move Intent Framework to Movement Bardock Testnet
- **`deploy-to-base-testnet.sh`** - Deploy EVM IntentEscrow to Base Sepolia Testnet
- **`check-testnet-preparedness.sh`** - Check balances and deployed contracts
- **`check-testnet-balances.sh`** - Check account balances on testnets

### Local Testing Scripts

- **`run-verifier-local.sh`** - Run verifier service locally against testnets
- **`run-solver-local.sh`** - Run solver service locally against testnets
- **`create-intent.sh`** - Create an intent on Movement testnet (requester script)

### Configuration Files

- **`config/testnet-assets.toml`** - Public configuration for asset addresses and decimals

## Usage

### Deploy to Movement Bardock Testnet

```bash
./testing-infra/testnet/deploy-to-movement-testnet.sh
```

### Deploy to Base Sepolia Testnet

```bash
./testing-infra/testnet/deploy-to-base-testnet.sh
```

### Check Testnet Preparedness

```bash
./testing-infra/testnet/check-testnet-preparedness.sh
```

### Local Testing (Before EC2 Deployment)

Test the verifier and solver services locally before deploying to EC2:

#### Terminal 1: Start Verifier

```bash
./testing-infra/testnet/run-verifier-local.sh
# Or with release build (faster):
./testing-infra/testnet/run-verifier-local.sh --release
```

#### Terminal 2: Start Solver

(after verifier is running)

```bash
./testing-infra/testnet/run-solver-local.sh
# Or with release build (faster):
./testing-infra/testnet/run-solver-local.sh --release
```

#### Terminal 3: Create Intent

(after both services are running)

```bash
# Create outflow intent (USDC.e Movement → USDC Base)
# Amount is in base units (10^-6 USDC), so 1000000 = 1 USDC
./testing-infra/testnet/create-intent.sh outflow 1000000

# Create inflow intent (USDC Base → USDC.e Movement)
# Also creates escrow on Base Sepolia automatically
./testing-infra/testnet/create-intent.sh inflow 1000000
```

The script will:

1. Show initial balances on both chains
2. Submit draft intent to verifier → solver signs it
3. Create intent on Movement hub chain
4. For inflow: create escrow on Base Sepolia
5. Wait for solver fulfillment and show final balance changes

#### Quick Health Check

```bash
# Check if verifier is running
curl -s http://localhost:3333/health | jq
```

#### Prerequisites for Local Testing

- Verifier and solver config files populated with deployed addresses:
  - `trusted-verifier/config/verifier_testnet.toml`
  - `solver/config/solver_testnet.toml`
- `.testnet-keys.env` with all required keys
- Movement CLI profile configured (solver only)
- Verifier running and healthy (for solver and create-intent scripts)

## Configuration

All scripts read from:

- `.testnet-keys.env` - Private keys and addresses (gitignored)
- `trusted-verifier/config/verifier_testnet.toml` - Verifier service config (gitignored)
- `solver/config/solver_testnet.toml` - Solver service config (gitignored)
- `config/testnet-assets.toml` - Public asset addresses and decimals

See `.taskmaster/tasks/TESTNET_DEPLOYMENT_PLAN.md` for detailed deployment instructions.
