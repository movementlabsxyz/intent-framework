# Single Validator Quickstart (From Scratch)

This guide runs a local validator using Movement's `aptos-core` (branch `l1-migration`) added as a submodule at `movement/aptos-core`.

## Prereqs
- Rust toolchain
- Aptos CLI

## Steps (5)
1. Build node binary from submodule:
   ```bash
   cd infra/external/movement-aptos-core
   cargo build -p aptos-node --release
   cd -
   ```
2. Prepare working dir and identities (adjust paths to your liking):
   ```bash
   export NODE_HOME=$(pwd)/infra/single-validator/work
   mkdir -p $NODE_HOME/data
   # Create or place validator-identity.yaml here if you already have one
   ```
3. Configure validator using Aptos CLI:
   ```bash
   aptos genesis set-validator-configuration \
     --local-repository-dir $NODE_HOME/data \
     --username mvt_val \
     --owner-public-identity-file $NODE_HOME/validator-identity.yaml \
     --validator-host 0.0.0.0:6180
   ```
4. Generate minimal config and edit paths:
   - Copy `validator_node.yaml` from this folder to `$NODE_HOME/validator_node.yaml` and update all `UPDATE_TO_YOUR_PATH` placeholders to point at `$NODE_HOME`.
5. Run the validator:
   ```bash
   infra/external/movement-aptos-core/target/release/aptos-node -f $NODE_HOME/validator_node.yaml
   # Verify:
   curl http://127.0.0.1:8080/v1
   ```

Notes:
- Use unique ports if you run multiple validators.
- Keep private materials (identity blobs, secure-data) local.

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

