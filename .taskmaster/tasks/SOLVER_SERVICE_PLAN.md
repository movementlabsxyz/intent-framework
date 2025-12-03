# Solver Service Implementation Plan

## Overview

Convert the solver from CLI binaries called on-demand to a **fully automated continuous service** that:

1. **Signs intents** - Polls verifier for pending drafts, evaluates acceptance, signs
2. **Fulfills inflow intents** - Monitors escrow deposits, provides tokens on hub chain
3. **Executes outflow transfers** - Transfers tokens on connected chain, fulfills hub intent

## Current State

The solver is a collection of CLI binaries:

- `sign_intent` - Generates Ed25519 signature for an intent
- `connected_chain_tx_template` - Generates connected chain transaction data

These are called by E2E shell scripts manually at specific points in the flow.

## Target State

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SOLVER SERVICE                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         SIGNING LOOP                                  │  │
│  │  Poll Verifier → Evaluate Acceptance → Sign → Submit to Verifier      │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│                                    ▼                                        │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         INTENT TRACKER                                │  │
│  │  Track signed intents → Monitor hub chain for creation                │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                          │                     │                            │
│            ┌─────────────┘                     └─────────────┐              │
│            ▼                                                 ▼              │
│  ┌─────────────────────────┐                   ┌─────────────────────────┐  │
│  │   INFLOW FULFILLMENT    │                   │   OUTFLOW FULFILLMENT   │  │
│  │                         │                   │                         │  │
│  │                         │                   │                         │  │
│  │  1. Monitor connected   │                   │  1. Transfer tokens on  │  │
│  │     chain for escrow    │                   │     connected chain     │  │
│  │  2. Fulfill on hub      │                   │  2. Get verifier sig    │  │
│  │     (provide tokens)    │                   │  3. Fulfill on hub      │  │
│  └─────────────────────────┘                   └─────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Intent Flows

### INFLOW Flow (Requester wants tokens on hub, escrows on connected)

| Step | Actor | Action | Solver Service Responsibility |
| ---- | ----- | ------ | ----------------------------- |
| 1 | Requester | Submits draft to verifier | - |
| 2 | **Solver** | Signs draft via verifier | **Signing Loop** |
| 3 | Requester | Creates intent on hub with signature | - |
| 4 | Requester | Deposits escrow on connected chain | - |
| 5 | **Solver** | Monitors for escrow, fulfills on hub | **Inflow Fulfillment** |
| 6 | Verifier | Generates escrow release approval | - |
| 7 | **Solver** | Releases escrow (receives tokens) | **Escrow Release** |

### OUTFLOW Flow (Requester wants tokens on connected, locks on hub)

| Step | Actor | Action | Solver Service Responsibility |
| ---- | ----- | ------ | ----------------------------- |
| 1 | Requester | Submits draft to verifier | - |
| 2 | **Solver** | Signs draft via verifier | **Signing Loop** |
| 3 | Requester | Creates intent on hub with signature | - |
| 4 | **Solver** | Transfers tokens on connected chain | **Outflow Transfer** |
| 5 | **Solver** | Requests verifier validation | **Outflow Fulfillment** |
| 6 | **Solver** | Fulfills hub intent with verifier sig | **Outflow Fulfillment** |

## Acceptance Conditions

The solver uses a **configurable token pair system** with exchange rates. All tokens are treated as fungible assets (no hardcoded USD/NATIVE distinctions).

### Token Pair Configuration

- **TokenPair**: Identified by `(offered_chain_id, offered_token, desired_chain_id, desired_token)`
- **Exchange Rate**: Configured per token pair (how many offered tokens per 1 desired token)
- **Acceptance Rule**: `offered_amount >= desired_amount * exchange_rate`

### Acceptance Logic

1. **Lookup Token Pair**: Check if the draft's token pair exists in configuration
2. **Reject Unsupported Pairs**: If token pair is not configured, reject immediately
3. **Calculate Required Amount**: `required_offered = desired_amount * exchange_rate`
4. **Accept if Profitable**: Accept if `offered_amount >= required_offered` (solver breaks even or profits)

### Example Configuration

```toml
[acceptance.token_pairs]
# Token A (chain 1) -> Token B (chain 2) at 1:1 rate
"1:0xaaa...:2:0xbbb..." = 1.0

# Token A (chain 1) -> NATIVE (chain 2) at 0.5 rate (1 NATIVE = 0.5 Token A)
"1:0xaaa...:2:NATIVE" = 0.5
```

**Note**: All tokens are fungible assets. No distinction between USD, native, or other token types - only the configured pairs and rates matter.

## Configuration Format

`solver/config/solver.template.toml`:

```toml
# Solver Service Configuration

[service]
# Verifier API endpoint
verifier_url = "http://localhost:3030"
# Polling interval in seconds
poll_interval_secs = 2
# Solver's Movement profile name (for signing and transactions)
movement_profile = "solver"

[chains]
# Hub chain configuration
[chains.hub]
chain_id = 1
rpc_url = "http://127.0.0.1:8080/v1"
module_address = "0x..."  # Intent framework module

# Connected chain configurations
[chains.connected.mvm]
chain_id = 2
rpc_url = "http://127.0.0.1:8082/v1"
module_address = "0x..."  # Intent framework module on connected chain
profile = "solver-chain2"  # Aptos CLI profile for this chain

[chains.connected.evm]
chain_id = 84532  # Base Sepolia
rpc_url = "https://sepolia.base.org"
private_key_env = "BASE_SOLVER_PRIVATE_KEY"  # Env var containing private key
escrow_contract = "0x..."  # IntentEscrow contract address

[acceptance]
# Supported token pairs with exchange rates
# Format: "offered_chain_id:offered_token:desired_chain_id:desired_token" = exchange_rate
# Exchange rate = how many offered tokens per 1 desired token

[acceptance.token_pairs]
# Example: Token A (chain 1) -> Token B (chain 2) at 1:1 rate
"1:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:2:0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" = 1.0

# Example: Token A (chain 1) -> NATIVE (chain 2) at 0.5 rate
"1:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:2:NATIVE" = 0.5

# Example: USDC (Base Sepolia) -> USDC (Eth Sepolia) at 1:1 rate
"84532:0x036CbD53842c5426634e7929541eC2318f3dCF7e:11155111:0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" = 1.0
```

## Task Breakdown

### Phase 1: Signing Service (Tasks 1-7)

This phase implements the core signing loop that polls the verifier for drafts and submits signatures.

---

### Task 1: Create tasks.json and plan backup

**Status**: ✅ completed

Create backup files for the solver service implementation plan:

- `.taskmaster/tasks/tasks.json` with all tasks
- `.taskmaster/tasks/SOLVER_SERVICE_PLAN.md` (this file)

**Commit**: `docs: add solver service implementation plan and tasks`

---

### Task 2: Extract signing logic to library

**Status**: ✅ completed  
**Dependencies**: Task 1

Refactor existing `sign_intent.rs` binary into reusable library modules.

**Implementation**: Reorganized structure to match verifier pattern:
- Created `solver/src/crypto/` module (matching verifier structure)
- Moved `hash.rs` → `crypto/hash.rs`
- Moved `signing.rs` → `crypto/signing.rs`
- Updated `sign_intent.rs` to use `solver::crypto` module
- Changed from `aptos` CLI to `movement` CLI for consistency
- Added strict address validation (requires 0x prefix)

**Files created**:

1. `solver/src/lib.rs` - Crate root with module declarations
2. `solver/src/crypto/signing.rs` - `sign_intent_hash()`, `get_private_key_from_profile()`
3. `solver/src/crypto/hash.rs` - `get_intent_hash()`
4. `solver/src/crypto/mod.rs` - Module exports

**Modified**: `solver/src/bin/sign_intent.rs` to use `solver::crypto` module

**Commit**: `refactor: reorganize solver structure and improve address validation`

---

### Task 3: Create acceptance module

**Status**: ✅ completed  
**Dependencies**: Task 2

Implement token validation and acceptance logic.

**File**: `solver/src/acceptance.rs`

**Implementation**: Uses configurable token pair system:
- `TokenPair` struct - identifies token pairs by `(offered_chain_id, offered_token, desired_chain_id, desired_token)`
- `AcceptanceConfig` struct - `HashMap<TokenPair, f64>` for exchange rates
- `DraftIntentData` struct - draft intent data from verifier API
- `AcceptanceResult` enum (Accept, Reject with reason)
- `should_accept_draft()` - evaluates token pair lookup and exchange rate

**Key Design Decision**: All tokens are fungible assets. No hardcoded USD/NATIVE distinctions. Only configured token pairs with exchange rates are supported.

**Commit**: `feat(solver): add acceptance module with configurable token pairs`

---

### Task 4: Create verifier client

**Status**: pending  
**Dependencies**: Task 2

HTTP client for verifier API communication.

**File**: `solver/src/verifier_client.rs`

- `VerifierClient` struct
- `poll_pending_drafts()` - GET /draft-intents/pending
- `submit_signature()` - POST /draft-intent/:id/signature
- `validate_outflow_fulfillment()` - POST /validate-outflow-fulfillment (for Phase 2)
- `get_approvals()` - GET /approvals (for Phase 2)

**Commit**: `feat(solver): add verifier client for API communication`

---

### Task 5: Create configuration module

**Status**: ✅ completed  
**Dependencies**: Task 3

Configuration structs and TOML loading.

**Files**:

1. `solver/src/config.rs` - `SolverConfig`, `ServiceConfig`, `ChainConfig`, `ConnectedChainConfig` (MVM/EVM), `AcceptanceConfig`, `SolverSigningConfig`
2. `solver/config/solver.template.toml` - Template with all settings

**Implementation**: Created comprehensive config module with:
- `SolverConfig` main struct with nested configs
- `ServiceConfig` for verifier URL and polling intervals
- `ChainConfig` for hub chain settings
- `ConnectedChainConfig` enum supporting both MVM and EVM chains
- `AcceptanceConfig` with token pair string keys (converted to `TokenPair` structs via `get_token_pairs()`)
- `SolverSigningConfig` for solver profile and address
- `SolverConfig::load()` method with validation (duplicate chain IDs, token pair format, exchange rates)
- `SolverConfig::get_token_pairs()` helper to convert string keys to `TokenPair` structs
- 15 unit tests covering validation, token pair conversion, TOML serialization, and file loading

**Commit**: `feat(solver): add configuration module and template`

---

### Task 6: Create signing service loop

**Status**: pending  
**Dependencies**: Task 3, Task 4, Task 5

Main signing loop that polls verifier and signs accepted drafts.

**File**: `solver/src/service/signing.rs`

- `SigningService` struct
- `run()` - main polling loop
- `process_draft()` - evaluate acceptance, sign if accepted
- `sign_and_submit()` - get hash, sign, submit to verifier

**Commit**: `feat(solver): add signing service loop`

---

### Task 7: Create main entry point (signing only)

**Status**: pending  
**Dependencies**: Task 6

Main binary for running solver signing service.

**Files**:

1. `solver/src/main.rs` - Entry point with Args (clap)
2. Update `solver/Cargo.toml` - Add tokio, toml, tracing deps

**Commit**: `feat(solver): add main entry point for signing service`

---

### Phase 2: Fulfillment Automation (Tasks 8-13)

This phase adds monitoring and automatic fulfillment of signed intents.

---

### Task 8: Create chain clients module

**Status**: pending  
**Dependencies**: Task 7

Clients for interacting with hub and connected chains.

**Files**:

1. `solver/src/chains/mod.rs` - Module root
2. `solver/src/chains/hub.rs` - Hub chain client (Movement)
   - `get_intent_events()` - Query intent creation events
   - `fulfill_inflow_intent()` - Call `fulfill_inflow_request_intent`
   - `fulfill_outflow_intent()` - Call `fulfill_outflow_request_intent`
3. `solver/src/chains/connected_mvm.rs` - Connected MVM chain client
   - `get_escrow_events()` - Query escrow deposit events
   - `transfer_with_intent_id()` - Execute outflow transfer
4. `solver/src/chains/connected_evm.rs` - Connected EVM chain client
   - `transfer_with_intent_id()` - Execute ERC20 transfer with intent_id in calldata

**Commit**: `feat(solver): add chain client modules for hub and connected chains`

---

### Task 9: Create intent tracker

**Status**: pending  
**Dependencies**: Task 8

Tracks signed intents and monitors for their creation on hub chain.

**File**: `solver/src/service/tracker.rs`

- `IntentTracker` struct
- `add_signed_intent()` - Store intent after signing
- `poll_for_created_intents()` - Query hub chain for intent creation events
- `get_pending_intents()` - Return intents ready for fulfillment
- Distinguish inflow vs outflow intents

**Commit**: `feat(solver): add intent tracker for monitoring signed intents`

---

### Task 10: Create inflow fulfillment service

**Status**: pending  
**Dependencies**: Task 8, Task 9

Monitors escrow deposits and fulfills inflow intents on hub.

**File**: `solver/src/service/inflow.rs`

- `InflowService` struct
- `poll_for_escrows()` - Monitor connected chain for escrow deposits
- `fulfill_inflow_intent()` - Call hub chain `fulfill_inflow_request_intent`
- `release_escrow()` - Get verifier approval and release escrow

**Commit**: `feat(solver): add inflow fulfillment service`

---

### Task 11: Create outflow fulfillment service

**Status**: pending  
**Dependencies**: Task 8, Task 9

Executes outflow transfers and fulfills hub intents.

**File**: `solver/src/service/outflow.rs`

- `OutflowService` struct
- `execute_connected_transfer()` - Transfer tokens on connected chain (MVM or EVM)
- `get_verifier_approval()` - Call `/validate-outflow-fulfillment`
- `fulfill_outflow_intent()` - Call hub chain `fulfill_outflow_request_intent`

**Commit**: `feat(solver): add outflow fulfillment service`

---

### Task 12: Integrate all services into main loop

**Status**: pending  
**Dependencies**: Task 10, Task 11

Combine signing, tracking, and fulfillment into unified service.

**Modify**: `solver/src/main.rs`

- Initialize all services
- Run concurrent loops:
  - Signing loop (poll verifier, sign drafts)
  - Tracking loop (monitor hub for intent creation)
  - Inflow loop (monitor escrows, fulfill)
  - Outflow loop (execute transfers, fulfill)

**Commit**: `feat(solver): integrate signing and fulfillment services`

---

### Task 13: Update E2E tests

**Status**: pending  
**Dependencies**: Task 12

Update shell scripts to use solver as a service.

**Files to create**:

1. `testing-infra/ci-e2e/start-solver.sh` - Generate config, start solver
2. `testing-infra/ci-e2e/stop-solver.sh` - Kill solver process

**Modify**:

- `run-tests-*.sh` - Start/stop solver service
- `*-submit-hub-intent.sh` - Remove manual signing (solver handles it)
- `*-fulfill-*.sh` - Remove manual fulfillment (solver handles it)
- `*-solver-transfer.sh` - Remove (solver handles automatically)
- `release-escrow.sh` - Remove or simplify (solver handles it)

**Commit**: `feat(e2e): update tests to use solver as a service`

---

## Files Summary

### New Files (Phase 1 - Signing)

| File | Description |
| ---- | ----------- |
| `.taskmaster/tasks/tasks.json` | Task database |
| `.taskmaster/tasks/SOLVER_SERVICE_PLAN.md` | This plan |
| `solver/src/lib.rs` | Crate root |
| `solver/src/signing.rs` | Signature generation |
| `solver/src/hash.rs` | Intent hash retrieval |
| `solver/src/acceptance.rs` | Acceptance logic |
| `solver/src/verifier_client.rs` | Verifier HTTP client |
| `solver/src/config.rs` | Configuration |
| `solver/src/service/mod.rs` | Service module root |
| `solver/src/service/signing.rs` | Signing service loop |
| `solver/src/main.rs` | Main entry point |
| `solver/config/solver.template.toml` | Config template |

### New Files (Phase 2 - Fulfillment)

| File | Description |
| ---- | ----------- |
| `solver/src/chains/mod.rs` | Chain clients module |
| `solver/src/chains/hub.rs` | Hub chain client |
| `solver/src/chains/connected_mvm.rs` | Connected MVM client |
| `solver/src/chains/connected_evm.rs` | Connected EVM client |
| `solver/src/service/tracker.rs` | Intent tracker |
| `solver/src/service/inflow.rs` | Inflow fulfillment |
| `solver/src/service/outflow.rs` | Outflow fulfillment |
| `testing-infra/ci-e2e/start-solver.sh` | Solver start script |
| `testing-infra/ci-e2e/stop-solver.sh` | Solver stop script |

### Modified Files

| File | Changes |
| ---- | ------- |
| `solver/src/bin/sign_intent.rs` | Use library functions |
| `solver/Cargo.toml` | Add deps, declare binaries |
| `testing-infra/ci-e2e/e2e-tests-*/run-tests-*.sh` | Start/stop solver |
| `testing-infra/ci-e2e/e2e-tests-*/*-submit-hub-intent.sh` | Remove manual signing |
| `testing-infra/ci-e2e/e2e-tests-*/*-fulfill-*.sh` | Remove (solver handles) |
| `testing-infra/ci-e2e/e2e-tests-*/release-escrow.sh` | Simplify or remove |

## Commit Sequence

### Phase 1: Signing Service

1. `docs: add solver service implementation plan and tasks`
2. `refactor(solver): extract signing logic to library modules`
3. `feat(solver): add acceptance module for draft intent validation`
4. `feat(solver): add verifier client for API communication`
5. `feat(solver): add configuration module and template`
6. `feat(solver): add signing service loop`
7. `feat(solver): add main entry point for signing service`

### Phase 2: Fulfillment Automation

8. `feat(solver): add chain client modules for hub and connected chains`
9. `feat(solver): add intent tracker for monitoring signed intents`
10. `feat(solver): add inflow fulfillment service`
11. `feat(solver): add outflow fulfillment service`
12. `feat(solver): integrate signing and fulfillment services`
13. `feat(e2e): update tests to use solver as a service`

## Notes

### Prerequisites

- Solver must be registered on-chain (public key in solver_registry) before signing
- Solver must have sufficient token balance to fulfill intents
- Solver must have gas tokens (MOVE/APT/ETH) on all chains

### Concurrency

The service runs multiple concurrent loops:

- **Signing loop**: Polls verifier every N seconds for new drafts
- **Tracking loop**: Polls hub chain for intent creation events
- **Inflow loop**: Polls connected chains for escrow deposits
- **Outflow loop**: Executes pending outflow transfers

All loops use tokio async/await for efficient concurrency.

### Error Handling

- Failed signatures: Log and skip (another solver may win)
- Failed fulfillments: Retry with exponential backoff
- Chain RPC errors: Retry with backoff, alert if persistent
- Verifier API errors: Retry with backoff

### Monitoring (Future)

- Prometheus metrics for:
  - Drafts seen/signed/rejected
  - Intents tracked/fulfilled
  - Transfers executed
  - RPC latencies
  - Error rates
