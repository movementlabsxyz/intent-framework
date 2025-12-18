# Intent Registry Implementation Plan

## Goal

Replace static `known_accounts` config with a dynamic on-chain registry that tracks which accounts have active intents.

## Security Model

Stores actual intent IDs (not just counts) to prevent malicious cleanup:
- Only truly expired or fulfilled intents can be removed
- Double-cleanup is prevented (intent_id removed from map)
- `cleanup_expired` verifies `now > expiry_time` before removing

## Changes

### 1. Move Contract: `intent_registry.move`

```move
struct IntentRegistry has key {
    intent_info: SimpleMap<address, IntentInfo>,        // intent_id -> (requester, expiry_time)
    requester_intents: SimpleMap<address, vector<address>>, // requester -> [intent_id, ...]
}

// Only friend modules (fa_intent_inflow, fa_intent_outflow) can call these
public(friend) fun register_intent(requester, intent_id, expiry_time)
public(friend) fun unregister_intent(intent_id)

public entry fun cleanup_expired(caller, intent_id)  // permissionless, verifies expiry

#[view]
public fun get_active_requesters(): vector<address>
#[view]
public fun is_intent_registered(intent_id): bool
#[view]
public fun get_intent_count(requester): u64
```

**Integration:**
- `fa_intent_inflow.move`: `register_intent` on create, `unregister_intent` on fulfill
- `fa_intent_outflow.move`: `register_intent` on create, `unregister_intent` on fulfill

### 2. Rust: Update Monitor

Replace `known_accounts` usage with registry query:

- `trusted-verifier/src/mvm_client.rs`: Add `get_active_requesters()`
- `trusted-verifier/src/monitor/hub_mvm.rs`: Query registry instead of config
- `trusted-verifier/src/monitor/inflow_mvm.rs`: Same
- `solver/src/chains/hub.rs`: Same
- `solver/src/chains/connected_mvm.rs`: Same

### 3. Config: Remove `known_accounts`

- `trusted-verifier/src/config/mod.rs`: Remove field from `ChainConfig`
- `trusted-verifier/config/verifier.template.toml`: Remove lines
- `testing-infra/ci-e2e/*/configure-verifier.sh`: Remove generation logic
- `docs/trusted-verifier/guide.md`: Update docs

## Expired Intent Cleanup

- **Fulfilled**: `unregister_intent(intent_id)` called in fulfill functions
- **Expired**: Anyone calls `cleanup_expired(intent_id)` which:
  1. Verifies intent exists in registry
  2. Verifies `now > expiry_time`
  3. Removes from both maps

## What Gets Removed

| Location | Removed |
|----------|---------|
| `ChainConfig` struct | `known_accounts` field |
| Config templates | `known_accounts = [...]` |
| CI scripts | `known_accounts` generation |
| Docs | `known_accounts` references |

## Commit Plan

### Commit 1: `feat(move): add intent_registry module` ✅
- Create `intent_registry.move` with `IntentRegistry` resource
- Store intent_id -> (requester, expiry_time) for security
- Add `register_intent()`, `unregister_intent()`, `cleanup_expired()`
- Add `get_active_requesters()` view function
- Unit tests for registry logic

### Commit 2: `feat(move): integrate registry into intent create/fulfill`
- Call `register_intent()` in `create_inflow_intent_entry()` and `create_outflow_intent_entry()`
- Call `unregister_intent()` in `fulfill_inflow_intent()` and `fulfill_outflow_intent()`

### Commit 3: `feat(verifier): add get_active_requesters to MvmClient`
- Add `get_active_requesters()` method to `mvm_client.rs`
- Query the registry view function via RPC

### Commit 4: `refactor(verifier): use registry instead of known_accounts`
- Update `poll_hub_events()` in `hub_mvm.rs`
- Update `poll_inflow_events()` in `inflow_mvm.rs`

### Commit 5: `refactor(solver): use registry instead of known_accounts`
- Update `solver/src/chains/hub.rs`
- Update `solver/src/chains/connected_mvm.rs`

### Commit 6: `chore: remove known_accounts from config`
- Remove `known_accounts` field from `ChainConfig` struct
- Remove from `verifier.template.toml`
- Remove from CI scripts (`configure-verifier.sh`)
- Update docs
