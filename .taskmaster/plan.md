# Implementation Plan

## Overview

This plan defines the cross-chain intent flow and supporting verifier needed to move assets from a connected chain to a hub chain under verifiable conditions.

- **Hub chain**: hosts regular (non-oracle) request intents from users (e.g., Alice).
- **Connected chain**: holds escrows (oracle-based) that lock funds and reference the hub intent via a shared `intent_id`.
- **Verifier**: observes hub intent creation and fulfillment plus connected-chain escrows, links them by `intent_id`, and produces an approval signature to release escrow after hub fulfillment is observed.
- **Tooling**: Docker localnets for Aptos chains, Hardhat for EVM chain, Move modules for intents/escrows, Solidity contracts for EVM escrows, and a Rust verifier with REST API and auto-escrow-release integration scripts.

**Note**: Hub Chain = Chain 1 (intent creation). Connected Chain = Chain 2 (Move VM escrow) or Chain 3 (EVM escrow). Verifier observes hub fulfillment first, then approves escrow release.

## Future Work

### Testing

1. **Balance Discrepancy Investigation**
   - Bob's balance decrease doesn't match expected amount when fulfilling intent with 100M tokens
   - Event confirms `provided_amount: 100,000,000` was transferred
   - But Bob's balance only decreases by ~99.9M (less than 100M, not 100M + gas)
   - Possible causes: Coin vs FA balance accounting; initial capture timing; gas treatment
   - Investigate how `aptos account balance` relates to FA operations and why loss < transfer amount
   - Location: `testing-infra/e2e-tests-mvm/fulfill-hub-intent.sh`

2. **Test Improvements**
   - Add timeout scenario tests
   - Test with multiple concurrent intents (unit tests added in `trusted-verifier/tests/monitor_tests.rs`)
   - Add negative test cases (rejected intents, failed fulfillments)

### Documentation

1. Finalize node bootstrapping instructions (ports, genesis, module publish) for both chains
2. Add more comprehensive API documentation
3. Add troubleshooting guide for common issues

### Move-intent-framework

- Add more intent types and use cases
- Optimize gas costs

### Trusted Verifier

1. **Performance Testing**
   - Load testing the API
   - Stress testing event monitoring
   - Memory usage monitoring

2. **Validation Hardening**
   - Add metadata and timeout checks
   - Support multiple concurrent intents robustly
   - Improve error handling and reporting

3. **Event Discovery Improvements**
   - Currently polls known accounts via `/v1/accounts/{address}/transactions`
   - Incomplete coverage (misses unlisted accounts)
   - Manual configuration (requires prelisting emitters)
   - Not scalable (unsuitable for many users)
   - Consider using event streams or indexer integration

4. **Feature Enhancements**
   - Add "ok" endpoint for a given `intent_id` to signal escrow is satisfied so solver can commit on hub
   - Add support for more chain types
   - Add metrics and observability
