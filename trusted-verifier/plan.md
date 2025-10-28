# Trusted Verifier Development Plan

## ✅ Completed

### Phase 1: Project Setup

- ✅ Created Rust project structure
- ✅ Added all dependencies (tokio, reqwest, warp, etc.)
- ✅ Implemented configuration system with TOML
- ✅ Built cryptographic service (Ed25519 signing)
- ✅ Created REST API server (Warp)
- ✅ Added key generation utility (`generate_keys.rs`)
- ✅ Set up stable Rust toolchain
- ✅ Pinned aptos-core version for stable builds

### Phase 2: Basic Functionality Testing

- ✅ API server starts successfully
- ✅ Health endpoint working (`GET /health`)
- ✅ Public key endpoint working (`GET /public-key`)
- ✅ Approval endpoint working (`POST /approval`)
- ✅ Events endpoint working (`GET /events`)
- ✅ Configuration loads correctly
- ✅ Crypto service generates valid signatures

### Phase 3: Local Testing Environment

- ✅ Ran `move-intent-framework/tests/cross_chain/setup-and-deploy.sh` to set up dual Docker chains (ports 8080 and 8082)
- ✅ Deployed contracts to both chains automatically via the setup script
- ✅ Created `config/verifier.toml` with real module addresses
- ✅ Generated Ed25519 key pair using `cargo run --bin generate_keys`
- ✅ Verified chains are running and accessible
- ✅ Verified verifier service starts and loads config correctly
- ✅ Tested API endpoints against running verifier

**Configuration Created**:
- `config/verifier.toml` contains chain addresses and cryptographic keys
- Both chains running on localhost (8080 and 8082)
- Verifier service runs on port 3000
- Contract addresses are ephemeral (change with each Docker restart)

## 🚧 Next Steps

---

### Phase 4: Aptos REST Client Implementation ✅ COMPLETED

**Goal**: Implement actual blockchain communication using HTTP REST API

**Tasks**:

1. ✅ Create Aptos REST client module
   - ✅ Implement HTTP client wrapper
   - ✅ Add basic API functions:
     - `get_account(address)` - Query account info
     - `get_account_events(address, event_handle)` - Get events
     - `get_transaction(hash)` - Get transaction details
   - ✅ Add integration tests with config address validation
2. ✅ Implement event polling for module events
   - **Approach**: Query known test accounts' transaction history
   - Module events (`event::emit()`) appear in user transactions
   - Configure Alice and Bob addresses in `config/verifier.toml`
   - Extract events from transaction history via `/v1/accounts/{address}/transactions`
   - Handle nested metadata objects in event data
   - Support both `LimitOrderEvent` and `OracleLimitOrderEvent`
3. ~~Add Indexer GraphQL API integration~~ (Deferred to production)
   - **Why not used**: For testing, known accounts approach is sufficient
   - **EventHandle alternative**: Could use global EventHandle resource at known address
     - Would allow querying via `/v1/accounts/{address}/events/{creation_number}`
     - However, Aptos has deprecated EventHandle in favor of module events
     - Reference: https://aptos.guide/network/blockchain/events
   - **Production**: Indexer GraphQL API recommended for querying by event type across all accounts
4. ✅ Replace placeholder logic in monitor module
   - Implemented real event polling that extracts events from transaction history
   - Parse and handle nested metadata objects correctly

**Files Created**: 
   - ✅ `trusted-verifier/src/aptos_client.rs`
   - ✅ `trusted-verifier/src/lib.rs`
   - ✅ `trusted-verifier/tests/integration/aptos_client_test.rs`
   - ✅ `trusted-verifier/tests/integration/README.md`
   - ✅ `trusted-verifier/tests/integration/mod.rs`
   - ✅ `trusted-verifier/tests/integration_test.rs`
   - ✅ `trusted-verifier/tests/unit/crypto_tests.rs`
   - ✅ `trusted-verifier/tests/unit/mod.rs`
   - ✅ `trusted-verifier/tests/unit_test.rs`
**Files Modified**: 
   - ✅ `trusted-verifier/src/monitor/mod.rs` (implemented real event polling from known accounts)
   - ✅ `trusted-verifier/src/aptos_client.rs` (added event structs, handle nested metadata)
   - ✅ `trusted-verifier/src/config/mod.rs` (added known_accounts field)
   - ✅ `trusted-verifier/config/verifier.toml` (added Alice/Bob known accounts)
   - ✅ `trusted-verifier/config/verifier.template.toml` (added known_accounts documentation)
   - ✅ `trusted-verifier/Cargo.toml` (added lib configuration)
   - ✅ `infra/setup-docker/stop-dual-chains.sh` (added profile cleanup)
   - ✅ `move-intent-framework/tests/cross_chain/setup-and-deploy.sh` (added profile cleanup)
   - ✅ `move-intent-framework/sources/fa_intent.move` (extended events with intent_id and revocable)
   - ✅ `move-intent-framework/sources/fa_intent_with_oracle.move` (extended events)

---

### Phase 5: Core Monitoring & Validation Logic

**Goal**: Implement the actual business logic for cross-chain validation

**Tasks**:

1. Implement event monitoring loop ✅
   - ✅ Start background monitoring for both chains
   - ✅ Poll for new events at regular intervals
   - ✅ Cache events in memory (both intent and escrow events)
   - ✅ Handle event deduplication (by chain+intent_id/escrow_id)
2. Implement validation logic 🚧
   - ✅ Cross-reference intent events from hub with escrow events
   - ✅ Basic validation structure in place
   - 🚧 Validate deposit amounts match intent requirements
   - 🚧 Check metadata matches (asset types, recipients)
   - 🚧 Verify timing constraints (timeouts)
3. Implement approval/rejection workflow 🚧
   - ✅ Reject revocable intents (security check)
   - ✅ Crypto service with signature generation ready
   - 🚧 Generate approval signatures for valid fulfillments
   - 🚧 Generate rejection signatures for invalid fulfillments
   - 🚧 Store signatures in cache
4. Connect monitoring to API endpoints ✅
   - ✅ Expose monitoring status via API
   - ✅ Provide cached events via API (both intent_events and escrow_events)
   - 🚧 Allow manual trigger of validation

**Files to Modify**: `trusted-verifier/src/monitor/mod.rs`, `trusted-verifier/src/validator/mod.rs`

---

### Phase 6: Comprehensive Testing

**Goal**: Ensure reliability and correctness

**Tasks**:

1. Add unit tests ✅
   - ✅ Test crypto operations (15 unit tests passing)
   - ✅ Test configuration loading
   - ✅ Test API endpoints
   - ✅ Test event structures and validation logic
   - ✅ Test cross-chain matching logic
2. Add integration tests ✅ (Partial)
   - ✅ Test against local Aptos chains (9 integration tests passing)
   - ✅ Test connectivity to both chains
   - ✅ Test event polling from chains
   - ✅ Test contract deployment verification
   - 🚧 Test full workflow (intent → escrow → validation)
   - 🚧 Test error handling
3. Add end-to-end tests 🚧
   - 🚧 Test complete cross-chain scenarios
   - 🚧 Test with multiple intents
   - 🚧 Test timeout scenarios
4. Performance testing 🚧
   - 🚧 Load testing the API
   - 🚧 Stress testing event monitoring
   - 🚧 Memory usage monitoring

**Files to Create**: `trusted-verifier/tests/integration_test.rs` ✅ (Created)
**Files to Modify**: Add tests to all modules ✅ (Done for existing modules)

---

## 🎯 Priority Order

**Recommended Sequence**:

1. ~~**Phase 3** (Local Testing Environment)~~ **COMPLETED** ✅
   - Real chains running
   - Contracts deployed
   - Baseline established
2. ~~**Phase 4** (Aptos REST Client)~~ **COMPLETED** ✅
   - ✅ Created Aptos REST client module
   - ✅ Implemented event polling from known accounts
   - ✅ Extract events from transaction history
   - ✅ All tests passing
3. **Phase 5** (Core Logic) - **IN PROGRESS** 🔄
   - ✅ Implemented event monitoring loop with background polling
   - ✅ Added event caching for both hub and escrow events
   - ✅ Implemented event deduplication by chain+intent_id/escrow_id
   - ✅ Standardized event structures with consistent fields
   - ✅ Added `intent_id` field for cross-chain linking
   - 🚧 Implement validation logic and approval/rejection workflow
   - Complete the workflow
4. **Phase 6** (Testing)
   - Ensure everything works
   - Add comprehensive test coverage

## 📝 Notes


- **Chains**: Dual Docker chains on ports 8080 (Hub) and 8082 (Connected)  
- **Deployed Modules**: Both chains have aptos_intent modules deployed
- **Configuration**: `trusted-verifier/config/verifier.toml` contains Alice/Bob known accounts and keys
- **Verifier**: Running on port 3000, API endpoints functional
- **Testing**: All tests passing - 15 unit tests + 9 integration tests
- **Event Polling**: Query known test accounts' transaction history to extract module events
  - Events from `/v1/accounts/{address}/transactions` endpoint
  - Handle nested metadata objects (`Object<Metadata>`)
  - Support both `LimitOrderEvent` and `OracleLimitOrderEvent`
  - Known accounts configured in TOML: Alice and Bob on both chains
- **Event Linking**: Added `intent_id` field to events for cross-chain linking between hub intents and escrow events
- **Event Structure**: Standardized `IntentEvent` and `EscrowEvent` with consistent fields (chain, issuer, source_amount, desired_amount, expiry_time, revocable)
- **Event Caching**: Both hub intent events and connected escrow events are cached separately and exposed via API
- **Deduplication**: Events deduplicated by chain+intent_id or chain+escrow_id
- **Next Step**: Complete validation workflow with approval/rejection signatures
- **Aptos Core**: Pinned to stable version (a10a3c02f16a2114ad065db6b4a525f0382e96a6)

## 🔗 Related Files

- Configuration: `trusted-verifier/config/verifier.toml`
- API Server: `trusted-verifier/src/api/mod.rs`
- Monitor: `trusted-verifier/src/monitor/mod.rs`
- Validator: `trusted-verifier/src/validator/mod.rs`
- Crypto: `trusted-verifier/src/crypto/mod.rs`
- Main: `trusted-verifier/src/main.rs`
- Docker Setup: `infra/setup-docker/`
- Intent Framework: `move-intent-framework/`
