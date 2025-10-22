# Docker Aptos Localnet Setup

This directory contains a Docker-based setup for running Aptos localnet with all services, providing a clean and isolated development environment.

## Quick Start

```bash
# Start the Aptos localnet
./infra/setup-docker/setup-docker-chain.sh
```

## What it includes

- **Node API** on port 8080 (REST API for core functionality)
- **Faucet** on port 8081 (for funding accounts)
- **Persistent storage** using Docker volumes
- **Health checks** to ensure services are running

This setup follows the single-validator approach with `aptos node run-localnet --with-faucet --force-restart --assume-yes`.

**Fresh Start Every Time**: Each run starts from block 0 with a completely clean state - all previous accounts and transactions are cleared.

## Endpoints

- **REST API**: http://127.0.0.1:8080
- **Faucet**: http://127.0.0.1:8081

## Management

```bash
# Stop the localnet
docker-compose -f infra/setup-docker/docker-compose.yml down

# View logs
docker-compose -f infra/setup-docker/docker-compose.yml logs -f

# Restart
docker-compose -f infra/setup-docker/docker-compose.yml restart
```

## Files

- `docker-compose.yml`: Uses official `aptoslabs/tools:nightly` image with host networking
- `setup-docker-chain.sh`: One-command setup script with health checks
- `Dockerfile`: Not needed - uses official Aptos image directly

## Benefits

- ✅ **Fresh start every time** - Always starts from block 0 with clean state
- ✅ **Clean isolation** - No conflicts with local processes
- ✅ **Easy cleanup** - Just `docker-compose down`
- ✅ **Consistent environment** - Same setup everywhere
- ✅ **No port conflicts** - Uses host networking
- ✅ **Reproducible testing** - Clean slate for each test run
- ✅ **Health monitoring** - Automatic service health checks

## Usage with Aptos CLI

Once running, you can create a local profile:

```bash
aptos init --profile local --network local
```

Then use it for commands:

```bash
aptos move publish --profile local --package-dir ./move-intent-framework
```

## Usage with TypeScript SDK

```typescript
import { Aptos, AptosConfig, Network } from "@aptos-labs/ts-sdk";

const network = Network.LOCAL;
const config = new AptosConfig({ network });
const client = new Aptos(config);
```