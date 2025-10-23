# Docker Aptos Localnet Setup

This directory contains Docker-based setups for running Aptos localnet, providing clean and isolated development environments for both single-chain and dual-chain testing.

## Quick Start

### Single Chain Setup
```bash
# Start a single Aptos localnet
./infra/setup-docker/setup-docker-chain.sh
```

### Dual Chain Setup
```bash
# Start two independent Aptos chains for cross-chain testing
./infra/setup-docker/setup-dual-chains.sh

# Stop both chains when done
./infra/setup-docker/stop-dual-chains.sh
```

## Single Chain Setup

### What it includes
- **Node API** on port 8080 (REST API for core functionality)
- **Faucet** on port 8081 (for funding accounts)
- **Persistent storage** using Docker volumes
- **Health checks** to ensure services are running

This setup follows the single-validator approach with `aptos node run-localnet --with-faucet --force-restart --assume-yes`.

**Fresh Start Every Time**: Each run starts from block 0 with a completely clean state - all previous accounts and transactions are cleared.

### Endpoints
- **REST API**: http://127.0.0.1:8080
- **Faucet**: http://127.0.0.1:8081

### Management
```bash
# Stop the localnet
docker-compose -f infra/setup-docker/docker-compose.yml down

# View logs
docker-compose -f infra/setup-docker/docker-compose.yml logs -f

# Restart
docker-compose -f infra/setup-docker/docker-compose.yml restart
```

## Dual Chain Setup

### What it includes
- **Chain 1**: Node API on port 8080, Faucet on port 8081
- **Chain 2**: Node API on port 8082, Faucet on port 8083
- **Independent chains**: Each chain has its own chain ID and state
- **Separate volumes**: `aptos-data` and `aptos-data-chain2`

Perfect for testing cross-chain interactions, bridge protocols, and multi-chain applications.

### Endpoints
- **Chain 1**:
  - REST API: http://127.0.0.1:8080
  - Faucet: http://127.0.0.1:8081
- **Chain 2**:
  - REST API: http://127.0.0.1:8082
  - Faucet: http://127.0.0.1:8083

### Management
```bash
# Stop both chains (recommended)
./infra/setup-docker/stop-dual-chains.sh

# Stop individual chains
docker-compose -f infra/setup-docker/docker-compose.yml down
docker-compose -f infra/setup-docker/docker-compose-chain2.yml down

# View logs
docker-compose -f infra/setup-docker/docker-compose.yml logs -f
docker-compose -f infra/setup-docker/docker-compose-chain2.yml logs -f
```

## Files

### Single Chain Files
- `docker-compose.yml`: Uses official `aptoslabs/tools:nightly` image with host networking
- `setup-docker-chain.sh`: One-command setup script with health checks
- `test-alice-bob.sh`: Complete Alice and Bob account testing script

### Dual Chain Files
- `docker-compose-chain2.yml`: Second chain configuration with port mapping
- `setup-dual-chains.sh`: Dual-chain setup script with health checks
- `stop-dual-chains.sh`: Clean shutdown script for both chains

## Benefits

### Single Chain Benefits
- ✅ **Fresh start every time** - Always starts from block 0 with clean state
- ✅ **Clean isolation** - No conflicts with local processes
- ✅ **Easy cleanup** - Just `docker-compose down`
- ✅ **Consistent environment** - Same setup everywhere
- ✅ **No port conflicts** - Uses host networking
- ✅ **Reproducible testing** - Clean slate for each test run
- ✅ **Health monitoring** - Automatic service health checks

### Dual Chain Benefits
- ✅ **Cross-chain testing** - Test bridge protocols and multi-chain apps
- ✅ **Independent chains** - Each chain has separate state and chain ID
- ✅ **Port isolation** - Different ports prevent conflicts
- ✅ **Parallel development** - Test on both chains simultaneously
- ✅ **Realistic scenarios** - Simulate real multi-chain environments

## Usage with Aptos CLI

Once running, you can create a local profile:

```bash
aptos init --profile local --network local
```

Then use it for commands:

```bash
aptos move publish --profile local --package-dir ./move-intent-framework
```

## Testing and Validation

For common testing commands and validation steps, see the [shared testing guide](../testing-guide.md).

### Alice and Bob Account Testing

Run the complete Alice and Bob account testing script:

```bash
# Test account creation, funding, and transfers
./infra/setup-docker/test-alice-bob.sh
```

This script will:
- ✅ Verify Docker localnet is running
- ✅ Create Alice and Bob accounts
- ✅ Fund both accounts via faucet
- ✅ Test transfer from Alice to Bob
- ✅ Verify balances before and after transfer
- ✅ Test REST API balance verification

## Usage with TypeScript SDK

```typescript
import { Aptos, AptosConfig, Network } from "@aptos-labs/ts-sdk";

const network = Network.LOCAL;
const config = new AptosConfig({ network });
const client = new Aptos(config);
```