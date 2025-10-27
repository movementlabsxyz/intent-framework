# Integration Tests

Integration tests for the trusted verifier service that require external services to be running.

## Prerequisites

These tests require the Aptos Docker chains to be running. The chains are started by the deployment script.

- Docker must be running
- Ports 8080 and 8082 must be available
- Aptos CLI must be installed and configured

## Setup

Before running integration tests, start the dual Aptos chains:

```bash
./move-intent-framework/tests/cross_chain/setup-and-deploy.sh
```

This script will:
1. Start Chain 1 (Hub Chain) on port 8080
2. Start Chain 2 (Connected Chain) on port 8082
3. Deploy the intent framework contracts to both chains
4. Display the deployment addresses for each chain

**Important**: After deployment, you must update `config/verifier.toml` with the new contract addresses:

```bash
# The script output will show the addresses like:
# Chain 1 Account:  0x1111111111111111111111111111111111111111111111111111111111111111
# Chain 2 Account:  0x2222222222222222222222222222222222222222222222222222222222222222

# Update config/verifier.toml:
# [hub_chain]
# intent_module_address = "0x1111111111111111111111111111111111111111111111111111111111111111"
#
# [connected_chain]  
# intent_module_address = "0x2222222222222222222222222222222222222222222222222222222222222222"
# escrow_module_address = "0x2222222222222222222222222222222222222222222222222222222222222222"
```

The tests will fail if the config addresses don't match the deployed contracts.

## Running the Tests

### Run all integration tests

```bash
cargo test --test integration_test
```

## Troubleshooting

**Tests fail to connect to chains:**
```bash
# Check if chains are running
curl http://127.0.0.1:8080/v1
curl http://127.0.0.1:8082/v1
```
