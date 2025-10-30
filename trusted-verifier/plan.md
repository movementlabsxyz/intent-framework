# Trusted Verifier Development Plan

### Phase 1: Project Setup ✅ COMPLETED

**Goal**: Establish a runnable Rust service with config, crypto, and API scaffolding

- ✅ Created Rust project structure
- ✅ Added all dependencies (tokio, reqwest, warp, etc.)
- ✅ Implemented configuration system with TOML
- ✅ Built cryptographic service (Ed25519 signing)
- ✅ Created REST API server (Warp)
- ✅ Added key generation utility (`generate_keys.rs`)
- ✅ Set up stable Rust toolchain
- ✅ Pinned aptos-core version for stable builds

### Phase 2: Basic Functionality Testing ✅ COMPLETED

**Goal**: Verify core API endpoints, configuration loading, and crypto signing

- ✅ API server starts successfully
- ✅ Health endpoint working (`GET /health`)
- ✅ Public key endpoint working (`GET /public-key`)
- ✅ Approval endpoint working (`POST /approval`)
- ✅ Events endpoint working (`GET /events`)
- ✅ Configuration loads correctly
- ✅ Crypto service generates valid signatures

### Phase 3: Local Testing Environment ✅ COMPLETED

**Goal**: Stand up dual local chains and wire the verifier to real nodes

- ✅ Ran `move-intent-framework/tests/cross_chain/setup-and-deploy.sh` to set up dual Docker chains (ports 8080 and 8082)
- ✅ Deployed contracts to both chains automatically via the setup script
- ✅ Created `config/verifier.toml` with real module addresses
- ✅ Generated Ed25519 key pair using `cargo run --bin generate_keys`
- ✅ Verified chains are running and accessible
- ✅ Verified verifier service starts and loads config correctly
- ✅ Tested API endpoints against running verifier
  - Chains: Dual Docker localnets on 8080 (Hub) and 8082 (Connected)
  - Deployed Modules: `aptos_intent` published on both chains
  - Configuration: `trusted-verifier/config/verifier.toml` with Alice/Bob known accounts and keys
  - Verifier Runtime: Service on port 3000, API endpoints functional
  - Aptos Core Pin: a10a3c02f16a2114ad065db6b4a525f0382e96a6

### Phase 4: Aptos REST Client Implementation ✅ COMPLETED

**Goal**: Implement actual blockchain communication using HTTP REST API

- ✅ Create Aptos REST client module
  - ✅ Implement HTTP client wrapper
  - ✅ Add basic API functions:
    - `get_account(address)` - Query account info
    - `get_account_events(address, event_handle)` - Get events
    - `get_transaction(hash)` - Get transaction details
  - ✅ Add integration tests with config address validation
- ✅ Implement event polling for module events
  - **Approach**: Query known test accounts' transaction history
  - Module events (`event::emit()`) appear in user transactions
  - Configure Alice and Bob addresses in `config/verifier.toml`
  - Extract events from transaction history via `/v1/accounts/{address}/transactions`
  - Handle nested metadata objects in event data
  - Support both `LimitOrderEvent` and `OracleLimitOrderEvent`
- ✅ Replace placeholder logic in monitor module
  - Implemented real event polling that extracts events from transaction history
  - Parse and handle nested metadata objects correctly

### Phase 5: Core Monitoring & Validation Logic — COMPLETED ✅

**Goal**: Implement the actual business logic for cross-chain validation and approvals used to release escrow via the integration script

- ✅ Implement event monitoring loop
  - ✅ Start background monitoring for both chains
  - ✅ Poll for new events at regular intervals
  - ✅ Cache events in memory (both intent and escrow events)
  - ✅ Handle event deduplication (by chain+intent_id/escrow_id)
- ✅ Event structures and linking
  - ✅ Standardized `IntentEvent` and `EscrowEvent` fields (chain, issuer, source_amount, desired_amount, expiry_time, revocable)
  - ✅ Added `intent_id` for cross-chain linking between hub intents and connected escrows
- ✅ Implement validation logic (minimal for test harness)
  - ✅ Cross-reference intent events from hub with escrow events
  - ✅ Basic validation structure in place (linking via intent_id)
  - ⏩ Detailed checks (metadata/timeouts) deferred; Move enforces fulfillment correctness on the hub.
- ✅ Implement approval workflow
  - ✅ Reject revocable intents (security check)
  - ✅ Crypto service with Ed25519 signature generation
  - ✅ Wait for hub intent to be fulfilled by solver
  - ✅ After hub fulfillment, generate approval signatures for valid escrows
  - ✅ Store approvals in cache and expose via API
  - ✅ Escrow release submission automated by integration script using approvals
- ✅ Connect monitoring to API endpoints
  - ✅ Expose monitoring status via API
  - ✅ Provide cached events via API (both intent_events and escrow_events)
  - ✅ Approvals API: `GET /approvals` provides signatures; integration script submits `complete_escrow_from_apt`

### Phase 6: Comprehensive Testing ✅ COMPLETED

**Goal**: Ensure reliability and correctness

- ✅ Add unit tests
  - ✅ Test crypto operations (15 unit tests passing)
  - ✅ Test configuration loading
  - ✅ Test API endpoints
  - ✅ Test event structures and validation logic
  - ✅ Test cross-chain matching logic
- ✅ Add integration tests
  - ✅ Test against local Aptos chains (9 integration tests passing)
  - ✅ Test connectivity to both chains
  - ✅ Test event polling from chains
  - ✅ Test contract deployment verification
  - ✅ Test full workflow (intent → escrow → fulfillment → approval)
  - ✅ Balance checks: scripts print initial/final balances and diffs on both chains

## Future Work

1. Add end-to-end tests
   - Test complete cross-chain scenarios
   - Test with multiple intents
   - Test timeout scenarios
2. Performance testing
   - Load testing the API
   - Stress testing event monitoring
   - Memory usage monitoring
