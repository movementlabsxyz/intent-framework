# Docker Aptos Chain Setup

This directory contains a Docker setup for building and running Aptos from source, based on the [official Aptos documentation](https://aptos.dev/network/nodes/localnet/local-development-network).

## Quick Start

```bash
# Start the Aptos chain
./infra/docker/setup-docker-chain.sh
```

## What it does

- **Builds Linux binaries** inside Docker (compatible with macOS host)
- **Runs Aptos node** on port 8080 (REST API)
- **Runs Aptet service** on port 8081 (Faucet)
- **Persistent storage** using Docker volumes
- **Health checks** to ensure services are running

## Endpoints

- **REST API**: http://127.0.0.1:8080
- **Faucet**: http://127.0.0.1:8081

## Management

```bash
# Stop the chain
docker-compose -f infra/docker/docker-compose.yml down

# View logs
docker-compose -f infra/docker/docker-compose.yml logs -f

# Restart
docker-compose -f infra/docker/docker-compose.yml restart
```

## Files

- `Dockerfile`: Multi-stage build (builds Linux binaries from source)
- `docker-compose.yml`: Orchestrates node and faucet containers
- `setup-docker-chain.sh`: One-command setup script

## Benefits

- ✅ **Clean isolation** - No conflicts with local processes
- ✅ **Easy cleanup** - Just `docker-compose down`
- ✅ **Consistent environment** - Same setup everywhere
- ✅ **No port conflicts** - Uses default Aptos ports
- ✅ **Fresh start** - Always starts from block 0