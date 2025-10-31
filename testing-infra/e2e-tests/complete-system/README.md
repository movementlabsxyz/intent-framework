# Integration Tests

Integration tests for the trusted verifier service that require external services to be running.

## Prerequisites

These tests require the Aptos Docker chains to be running. The chains are started by the deployment script.

- Docker must be running
- Ports 8080 and 8082 must be available
- Aptos CLI must be installed and configured

## Running the Tests

### Run all integration tests

```bash
# From project root:
./testing-infra/e2e-tests/run-tests.sh
```

The script will:
1. Run `submit-cross-chain-intent.sh 1` to:
   - Start Docker chains (Chain 1 on 8080, Chain 2 on 8082)
   - Deploy contracts to both chains
   - Create intents and escrows on-chain
2. Automatically extract deployed module addresses and update `trusted-verifier/config/verifier.toml`
3. Create a temporary test entry point
4. Run the integration tests using `cargo test`
5. Clean up the temporary file

**Note**: The tests require the `trusted_verifier` crate, so they are run from within the trusted-verifier directory context.

## Troubleshooting

**Tests fail to connect to chains:**
```bash
# Check if chains are running
curl http://127.0.0.1:8080/v1
curl http://127.0.0.1:8082/v1
```
