# Single Validator Quickstart (Automated)

This guide runs a local validator using Movement's `aptos-core` (branch `l1-migration`) with automated setup.

## Prerequisites
- Rust toolchain
- Aptos CLI

## Automated Setup (1 Step)
Run the automated setup script:
```bash
./infra/single-validator/run_local_validator.sh
```

This script will:
1. Ensure Movement `aptos-core` is cloned and on the correct branch
2. Build `aptos-node` (release) if needed
3. Generate validator identity files if not present
4. Configure the validator using Aptos CLI
5. Start the validator node
6. Wait for the REST API to be ready

## Manual Verification
```bash
# Check validator is running
curl http://127.0.0.1:8080/v1

# Check logs
ps aux | grep aptos-node
```

## Files Created
- `infra/single-validator/work/validator-identity.yaml` - Validator identity with keys
- `infra/single-validator/work/validator_node.yaml` - Node configuration
- `infra/single-validator/work/data/` - Genesis files and validator data (regenerated each run)

## Stopping the Validator
```bash
# Find and kill the process
pkill -f aptos-node
# or find PID and kill manually
ps aux | grep aptos-node
kill <PID>
```

Notes:
- The validator identity contains test keys for local development only
- All generated files are in `infra/single-validator/work/`
- The `data/` directory is regenerated on each run

## Pin and Verify aptos-core (Enforced on Build)
- Ensure Movement `aptos-core` is present (plain clone):
  ```bash
  bash move-intent-framework/tests/cross_chain/setup_aptos_core.sh
  ```
- Builds/tests run a verification hook via `move-intent-framework/Move.toml` that checks `infra/external/movement-aptos-core` HEAD against the lock file `infra/external/movement-aptos-core.lock`.
  - If they differ, the build exits non-zero with a clear message.
- To update the pinned commit intentionally:
  ```bash
  git -C infra/external/movement-aptos-core rev-parse HEAD > infra/external/movement-aptos-core.lock
  ```
  Commit the updated lock file.

