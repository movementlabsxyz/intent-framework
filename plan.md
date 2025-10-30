## Cross-chain Oracle Intents: Implementation Plan

## Overview

This plan defines the cross-chain intent flow and supporting verifier needed to move assets from a connected chain to a hub chain under verifiable conditions.

- **Hub chain**: hosts regular (non-oracle) request intents from users (e.g., Alice).
- Connected chain: holds escrows (oracle-based) that lock funds and reference the hub intent via a shared `intent_id`.
- **Verifier**: observes hub intent creation and fulfillment plus connected-chain escrows, links them by `intent_id`, and produces an approval signature to release escrow after hub fulfillment is observed.
- **Tooling**: Docker localnets for two chains, Move modules for intents/escrows, and a Rust verifier with REST API and auto-escrow-release integration script.

**Note**: Hub Chain = Chain A (intent creation). Connected Chain = Chain B (escrow/vault). Verifier observes hub fulfillment first, then approves escrow release.


## Future Work

### Testing
1. Add a minimal cross-chain test runner under `tests/cross_chain`:
  - Language: TypeScript (Aptos TS SDK) or Python (aptos-sdk)
  - Inputs: hub/connected REST URLs, profiles/keys, deployed module addrs
  - Flow: start from running Docker localnets → deploy modules → create intent (hub) → create escrow (connected) → start verifier → fulfill intent (hub) → await approval → release escrow (connected)
  - Assertions: event linkage via `intent_id`, escrow released, before/after balances, no rejected intents
  - Outputs: JSON summary (tx hashes, intent_id, escrow_id, balance diffs)
2. investigate Balance Discrepancy
   - Bob's balance decrease doesn't match expected amount when fulfilling intent with 100M tokens
   - Event confirms `provided_amount: 100,000,000` was transferred
   - But Bob's balance only decreases by 99,888,740 (less than 100M, not 100M + gas)
   - Possible causes: Coin vs FA balance accounting; initial capture timing; gas treatment
   - Investigate how `aptos account balance` relates to FA operations and why loss < transfer amount
   - Location: `move-intent-framework/tests/cross_chain/submit-cross-chain-intent.sh`
3. Convert shell scripts into Rust binaries where practical

### test-infra

### Documentation
1. Finalize node bootstrapping instructions (ports, genesis, module publish) for both chains

### Move-intent-framework

### Trusted Verifier

1. Add end-to-end tests
   - Test complete cross-chain scenarios
   - Test with multiple intents
   - Test timeout scenarios
2. Performance testing
   - Load testing the API
   - Stress testing event monitoring
   - Memory usage monitoring
3. Verifier documentation
   - Add docs under `trusted-verifier/docs/` (overview, setup/usage, API)
   - Link from root and verifier plans
4. Plan/documentation cleanup
   - Fix typos in root `plan.md` (non-revocable/non-revocability)
   - Cross-link new verifier docs
5. Balance discrepancy investigation (coordinate with scripts)
6. Validation hardening
   - Add metadata and timeout checks
   - Support multiple concurrent intents robustly
7. Add "ok" endpoint for a given `intent_id` to signal escrow is satisfied so solver can commit on hub
8. Correct test fixture requiring 1 token; should be 0
9. Improve event discovery (currently polls known accounts via `/v1/accounts/{address}/transactions`)
   - Incomplete coverage (misses unlisted accounts)
   - Manual configuration (requires prelisting emitters)
   - Not scalable (unsuitable for many users)
10. Implement the monitoring/oracle service as a simple CLI/daemon colocated in `tests/cross_chain` for now; later extract to `tools/oracle-service` if needed

