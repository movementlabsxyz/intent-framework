# Infrastructure Setup

This directory contains infrastructure setup for running chains for development and testing.

## Resources

- [Testing Guide](./testing-guide.md) - Testing and validation commands

## Setup

- Platform: Linux (AMD64) only
- Location: [`setup-docker/`](./setup-docker/)
- Best for: Quick development, testing, CI/CD, multi-chain testing
- Features: Fresh start every time, no system dependencies, dual-chain support

### Quick start

```bash
# Single chain
./testing-infra/single-chain/setup-docker-chain.sh

# Single-chain quick test (accounts, funding, transfer)
./testing-infra/single-chain/test-alice-bob.sh

# Multi-chain (two independent localnets)
./testing-infra/multi-chain/setup-dual-chains.sh

# Stop both chains
./testing-infra/multi-chain/stop-dual-chains.sh
```

### Endpoints

- Chain 1: REST http://127.0.0.1:8080 • Faucet http://127.0.0.1:8081
- Chain 2: REST http://127.0.0.1:8082 • Faucet http://127.0.0.1:8083

### Management

```bash
# Single chain logs / stop / restart
docker-compose -f testing-infra/single-chain/docker-compose.yml logs -f
docker-compose -f testing-infra/single-chain/docker-compose.yml down
docker-compose -f testing-infra/single-chain/docker-compose.yml restart

# Multi-chain logs / stop
docker-compose -f testing-infra/single-chain/docker-compose.yml logs -f
docker-compose -f testing-infra/multi-chain/docker-compose-chain2.yml logs -f
./testing-infra/multi-chain/stop-dual-chains.sh
```

## Setup with source code (deprecated)

Manual "setup from source" was removed.

- Last commit with manual setup: `5a8e453dfbaef22c513a5293169591f4d48c736f`
- Reason: Could not support multi‑chain due to hard‑coded port conflicts.
