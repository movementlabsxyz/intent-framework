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

### Repository Integration: Movement Aptos-Core as Submodule
- Add `aptos-core` (branch `l1-migration`) as a Git submodule to build and run local validators directly from this repo.

Submodule layout:
- Path: `infra/external/movement-aptos-core` (external dependency; Movement fork of aptos-core)

Add and pin the submodule:

```bash
git submodule add -b l1-migration https://github.com/movementlabsxyz/aptos-core.git infra/external/movement-aptos-core
git submodule update --init --recursive
# Optionally pin to a specific commit for reproducibility
cd infra/external/movement-aptos-core && git checkout <commit-sha>
cd -
git add .gitmodules infra/external/movement-aptos-core
git commit -m "Add aptos-core submodule (l1-migration) and pin"
```

Update submodule (later):

```bash
git submodule update --remote --init --recursive infra/external/movement-aptos-core
# or within the submodule
cd infra/external/movement-aptos-core && git fetch && git checkout l1-migration && git pull && cd -
```

Build `aptos-node` from the submodule:

```bash
cd infra/external/movement-aptos-core
cargo build -p aptos-node --release
cd -
```

Run a single local validator using the steps below, but referencing configs and binaries from `infra/external/movement-aptos-core`.

#### Node Setup Details (from provided instructions)
- Clone Movement Aptos Core (l1-migration branch):

```bash
git clone https://github.com/movementlabsxyz/aptos-core.git
cd aptos-core && git checkout l1-migration
```

- Build the node binary:

```bash
cargo build -p aptos-node --release
# or run directly
cargo run -p aptos-node --release -- --help
```

- Prepare per-node `.aptos` directories (one for each chain):
  - Example: `/path/to/chainA/.aptos` and `/path/to/chainB/.aptos`
  - Each should contain its own `data/`, `validator-identity.yaml`, `waypoint.txt`, etc.

- Use Aptos CLI to set validator configuration for each node (adjust paths per node):

```bash
aptos genesis set-validator-configuration \
  --local-repository-dir /path/to/chainA/.aptos/data \
  --username mvt_val \
  --owner-public-identity-file /path/to/chainA/.aptos/validator-identity.yaml \
  --validator-host 0.0.0.0:6180
```

- Create `validator_node.yaml` per node using this template (update all paths and adjust ports for Chain B):

```yaml
base:
  data_dir: /home/ubuntu/.aptos/data/maptos # contains DB
  role: validator
  waypoint:
    from_file: /home/ubuntu/.aptos/data/waypoint.txt # update to your path
consensus:
  vote_back_pressure_limit: 50
  safety_rules:
    service:
      type: local
    backend:
      type: on_disk_storage
      path: /home/ubuntu/.aptos/data/secure-data.json # update to your path
      namespace: null
    initial_safety_rules_config:
      from_file:
        waypoint:
          from_file: /home/ubuntu/.aptos/data/waypoint.txt # update to your path
        identity_blob_path: /home/ubuntu/.aptos/validator-identity.yaml # update to your path

execution:
  genesis_file_location: /home/ubuntu/.aptos/data/genesis.blob # update to your path
storage:
  backup_service_address: 0.0.0.0:6186
  rocksdb_configs:
    enable_storage_sharding: false
validator_network:
  discovery_method: none
  mutual_authentication: true
  identity:
    type: from_file
    path: /home/ubuntu/.aptos/validator-identity.yaml # update to your path
  listen_address: /ip4/0.0.0.0/tcp/6180
full_node_networks:
  - network_id:
      private: "vfn"
    listen_address: "/ip4/0.0.0.0/tcp/6181"
    identity:
      type: "from_config"
      key: "604191ee408af3250997fd346b91bd390779ba07d74d044dfe17da21fc593a01"
      peer_id: "e05148cdf30a050eb216c8dfc4b7b9e6c64cd412f0be395436242f2200a3d936"
api:
  enabled: true
  address: 0.0.0.0:8080
admin_service:
  enabled: true
  address: 0.0.0.0
  port: 9102
state_sync:
  state_sync_driver:
    bootstrapping_mode: ExecuteOrApplyFromGenesis
    continuous_syncing_mode: ExecuteTransactionsOrApplyOutputs
    enable_auto_bootstrapping: true
    max_connection_deadline_secs: 1
```

- Start each validator with its config:

```bash
aptos-node -f /path/to/chainA/validator_node.yaml
# and for chain B (use different ports in YAML, e.g., 6182/8081, etc.)
aptos-node -f /path/to/chainB/validator_node.yaml
```

 

 

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

