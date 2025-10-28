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
1. [Hub Chain] Alice creates regular (non-oracle) intent on Hub Chain requesting tokens.
2. [Connected Chain] Alice creates escrow with tokens locked (with verifier public key), linking to the hub intent via intent_id.
3. [Verifier Service] Monitoring service observes both chains:
   - Detects intent creation on Hub Chain
   - Detects escrow creation on Connected Chain  
   - Validates cross-chain conditions match (amounts, metadata, expiry, non-revocability)
4. [Hub Chain] Bob (solver) fulfills the intent on Hub Chain without verifier signature (regular fulfillment)
5. [Hub Chain] Intent transitions to fulfilled state on Hub Chain
6. [Verifier Service] Verifier detects solver fulfilled the hub intent, validates conditions, then signs approval signature for escrow release
7. [Connected Chain] Escrow can now be released with verifier approval signature

**Note**: Hub Chain = Chain A (intent creation). Connected Chain = Chain B (escrow/vault). Verifier observes hub fulfillment first, then approves escrow release.

### Monitoring/Oracle Service Design (Trusted Verifier)
- Responsibilities:
  - Watch Hub Chain (Chain A) for intent creation events
  - Watch Connected Chain (Chain B) for escrow creation events
  - Validate that hub intent and escrow are properly linked via intent_id
  - Check that cross-chain conditions match (amounts, metadata, expiry, non-revocalibility)
  - Monitor when hub intent is fulfilled by solver
  - After hub intent fulfillment, generate Ed25519 approval signature for escrow release
  - Expose REST API for retrieval of verifier signatures
- Current Implementation:
  - Rust service in `trusted-verifier/`
  - Monitors both chains via polling
  - Validates cross-chain conditions before approval
  - Waits for hub intent fulfillment before approving escrow release
  - Emits approval/rejection signatures via API
- Interfaces:
  - Config: RPC URLs for Chain A/B, accounts/keys, polling intervals, filters.
  - Inputs: intent-id on Chain A, vault address/collection on Chain B, satisfaction predicate.
  - Outputs: transaction hashes on Chain A for attestation and close actions; logs/metrics.
- Reliability:
  - Idempotent submissions; retry with backoff.
  - Persistence for last observed B state and A submission status.
  - Observability: structured logs and optional metrics.

### Test Orchestration Steps
1. Boot Hub Chain (Chain A) and Connected Chain (Chain B) using Docker.
2. Deploy `aptos-intent` modules to both chains via `setup-and-deploy.sh`.
3. Initialize/fund Alice and Bob test accounts on both chains.
4. **[Hub Chain]** Alice creates regular intent requesting tokens.
5. **[Connected Chain]** Alice creates escrow with tokens locked, linking to hub intent via intent_id.
6. **[Verifier Service]** Start verifier service to monitor both chains.
7. **[Verifier Service]** Verifier detects and validates both intent and escrow match conditions.
8. **[Hub Chain]** Bob (solver) fulfills intent on Hub Chain (regular fulfillment, no verifier signature needed).
9. **[Verifier Service]** Verifier detects hub intent was fulfilled and generates approval signature for escrow release.
10. Assert intent transitions to fulfilled state on Hub Chain.
11. Assert escrow can be released with verifier approval signature.

### Success Criteria / Assertions
- Intent on Hub Chain transitions through expected states: Created -> Fulfilled.
- Escrow on Connected Chain remains locked until verifier approval.
- Verifier validates cross-chain conditions before approval:
  - intent_id matches between hub intent and escrow
  - source_amount in escrow >= desired_amount in hub intent
  - metadata matches
  - expiry_time matches
  - both intent and escrow are non-revocalible
- Oracle signature is NOT required for fulfillment on Hub Chain (regular intent fulfillment).
- Oracle signature IS required for escrow release on Connected Chain.
- No orphaned or dangling reservations remain.

### Implementation Notes
- We already have oracle intent Move code; prefer using its public entry points and events for assertions.
- Start with a polling-based monitor; add event/websocket subscriptions later if available.
- Keep keys and secrets in test-only configs; never commit real secrets.

### Next Steps
- Finalize node bootstrapping instructions (ports, genesis, module publish) for both chains.
- Scaffold `tests/cross_chain` with a minimal runner (TypeScript using `aptos` SDK or Python using `aptos-sdk`), plus configuration.
- Implement the monitoring/oracle service as a simple CLI/daemon colocated in `tests/cross_chain` for now; later extract to `tools/oracle-service` if needed.

