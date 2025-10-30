# Trusted Verifier Development Plan

## Future Work

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
5. Balance discrepancy investigation
   - Investigate FA vs coin balances and initial capture timing
   - Document findings and update scripts accordingly
6. Validation hardening
   - Add metadata and timeout checks
   - Support multiple concurrent intents robustly
7. Verifier delivers an "ok" endpoint for a given intent_id signalling that the escrow to satisfy the request intent is satisfied. This gives the solver the knowledge that it can commit to the intent on the hub chain.
8. one of the intents requires in one of the fields 1 token. this is a mistake and should be 0.
