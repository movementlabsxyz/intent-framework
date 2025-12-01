# Future Work

## Testing

1. **Balance Discrepancy Investigation**
   - Bob's balance decrease doesn't match expected amount when fulfilling intent with 100M tokens
   - Event confirms `provided_amount: 100,000,000` was transferred
   - But Bob's balance only decreases by ~99.9M (less than 100M, not 100M + gas)
   - Possible causes: Coin vs FA balance accounting; initial capture timing; gas treatment
   - Investigate how `movement account balance` relates to FA operations and why loss < transfer amount
   - Location: `testing-infra/ci-e2e/e2e-tests-mvm/fulfill-hub-intent.sh`

2. **Test Improvements**
   - Add timeout scenario tests
   - Test with multiple concurrent intents (unit tests added in `trusted-verifier/tests/monitor_tests.rs`)
   - Add negative test cases (rejected intents, failed fulfillments)

## Documentation

1. Finalize node bootstrapping instructions (ports, genesis, module publish) for both chains
2. Add more comprehensive API documentation
3. Add troubleshooting guide for common issues

## Move-intent-framework

- Add more intent types and use cases
- Optimize gas costs

## Trusted Verifier

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
