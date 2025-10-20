## Cross-chain Oracle Intents: Implementation Plan

### Goals
- Enable oracle-backed intents to be created on Chain A and fulfilled on Chain B, with settlement and closure on Chain A once fulfillment is confirmed.
- Provide an automated service that monitors vault state on Chain B and submits oracle attestations on Chain A.
- Add an end-to-end integration test that spins up two local Aptos nodes, executes the cross-chain flow, and asserts correctness.
  - We will run two validator nodes (one per chain). Public full nodes (PFNs) are optional and not required for this test.

### Integration Test Placement
- Location: `move-intent-framework/tests/cross_chain/`
  - Rationale: Keeps integration flows distinct from unit-style Move tests in `move-intent-framework/tests/` while living close to the Move package. The folder will contain test orchestration scripts (TypeScript or Python), config, and fixtures.
- Artifacts:
  - `move-intent-framework/tests/cross_chain/README.md` – how to run locally
  - `move-intent-framework/tests/cross_chain/test_cross_chain_oracle_intent.(ts|py)` – orchestrates the flow
  - `move-intent-framework/tests/cross_chain/docker-compose.yml` (optional) – if we dockerize nodes
  - `move-intent-framework/tests/cross_chain/env/` – node configs, accounts, keys

### Environment Setup (Two Aptos Validator Nodes)
- Two independent localnet nodes (Chain A and Chain B). We will parameterize via distinct genesis/configs and unique ports.
- Steps (high-level; details to follow once node instructions are provided):
  1. Start Chain A node.
  2. Start Chain B node.
  3. Fund test accounts on both chains and publish the `aptos-intent` Move package if needed (or use existing published modules if baked into genesis).
  4. Configure RPC endpoints in test runner and monitoring service.

### Repository Integration: Movement Aptos-Core as Plain Clone
- Use a plain clone of `aptos-core` (branch `l1-migration`) with commit pinning for reproducibility.

Repository layout:
- Path: `infra/external/movement-aptos-core` (external dependency; Movement fork of aptos-core)
- Lock file: `infra/external/movement-aptos-core.lock` (pinned commit SHA)
- Verification: `infra/external/verify-aptos-pin.sh` (enforces correct commit)

Setup and pinning:

```bash
# Automated setup (recommended)
bash move-intent-framework/tests/cross_chain/setup_aptos_core.sh

# Manual setup
git clone --branch l1-migration https://github.com/movementlabsxyz/aptos-core.git infra/external/movement-aptos-core
git -C infra/external/movement-aptos-core submodule update --init --recursive
git -C infra/external/movement-aptos-core rev-parse HEAD > infra/external/movement-aptos-core.lock
```

Build enforcement:
- `move-intent-framework/Move.toml` includes a build hook that runs `infra/external/verify-aptos-pin.sh`
- This ensures `aptos move test` fails if the wrong commit is checked out
- Build hook runs automatically before any Move compilation/testing

Run a single local validator using the automated script:
```bash
./infra/single-validator/run_local_validator.sh
```

#### Automated Node Setup (Current Implementation)
The single validator setup is now fully automated:

```bash
# Single validator (Chain A)
./infra/single-validator/run_local_validator.sh

# For Chain B, modify ports in validator_node.yaml and run manually
# Or extend the script to support multiple validators
```

Key files created:
- `infra/single-validator/work/validator-identity.yaml` - Combined validator identity with all keys
- `infra/single-validator/work/validator_node.yaml` - Configured node config
- `infra/single-validator/work/data/` - Genesis files and validator data

The script handles:
1. Cloning/updating Movement aptos-core
2. Building aptos-node (with caching)
3. Generating validator identity files
4. Running `aptos genesis set-validator-configuration`
5. Starting the validator node
6. Waiting for REST API readiness

 

 

### Cross-chain Flow (Happy Path)
1. Create intent on Chain A using existing oracle-intent entry functions.
2. On Chain B, perform the action that will satisfy the intent (e.g., deposit to a vault).
3. Monitoring service detects the vault state on Chain B meets criteria.
4. Service submits an oracle attestation/fulfillment proof on Chain A referencing Chain B observation.
5. Intent transitions to a fulfilled state on Chain A.
6. Close the intent on Chain A once the fulfillment is confirmed on-chain.

### Monitoring/Oracle Service Design
- Responsibilities:
  - Watch Chain B for vault state updates relevant to specific intent IDs or filters.
  - Determine satisfaction criteria (e.g., balance >= threshold, event emission).
  - Produce an attestation payload for Chain A (e.g., signed message or on-chain oracle transaction per existing Move interface).
  - Submit oracle transaction(s) on Chain A to fulfill/confirm the intent.
- Interfaces:
  - Config: RPC URLs for Chain A/B, accounts/keys, polling intervals, filters.
  - Inputs: intent-id on Chain A, vault address/collection on Chain B, satisfaction predicate.
  - Outputs: transaction hashes on Chain A for attestation and close actions; logs/metrics.
- Reliability:
  - Idempotent submissions; retry with backoff.
  - Persistence for last observed B state and A submission status.
  - Observability: structured logs and optional metrics.

### Test Orchestration Steps
1. Boot Chain A and Chain B.
2. Deploy or ensure `aptos-intent` modules are available on both chains.
3. Initialize/fund test accounts and set up vault on Chain B.
4. Create intent on Chain A (record intent-id).
5. Trigger fulfillment condition on Chain B (e.g., deposit to vault).
6. Run monitoring/oracle service; it observes Chain B and submits fulfillment on Chain A.
7. Wait for Chain A to confirm fulfillment; assert state change.
8. Close the intent on Chain A; assert closed/settled state and invariants.

### Success Criteria / Assertions
- Intent on Chain A transitions through expected states: Created -> Fulfilled -> Closed.
- Oracle transactions on Chain A contain references to Chain B observation (event or state root proof if applicable).
- Vault state on Chain B matches expected post-condition.
- No orphaned or dangling reservations remain.

### Implementation Notes
- We already have oracle intent Move code; prefer using its public entry points and events for assertions.
- Start with a polling-based monitor; add event/websocket subscriptions later if available.
- Keep keys and secrets in test-only configs; never commit real secrets.

### Next Steps
- Finalize node bootstrapping instructions (ports, genesis, module publish) for both chains.
- Scaffold `tests/cross_chain` with a minimal runner (TypeScript using `aptos` SDK or Python using `aptos-sdk`), plus configuration.
- Implement the monitoring/oracle service as a simple CLI/daemon colocated in `tests/cross_chain` for now; later extract to `tools/oracle-service` if needed.

