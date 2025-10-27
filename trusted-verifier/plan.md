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

### Phase 4: Aptos REST Client Implementation

**Goal**: Implement actual blockchain communication using HTTP REST API

**Tasks**:

1. Create Aptos REST client module
   - Implement HTTP client wrapper
   - Add basic API functions:
     - `get_account(address)` - Query account info
     - `get_account_events(address, event_handle)` - Get events
     - `get_transaction(hash)` - Get transaction details
2. Implement event polling
   - Poll hub chain for intent events
   - Poll connected chain for escrow events
   - Parse event data into structs
3. Add transaction verification
   - Verify transaction signatures
   - Check transaction status
   - Validate transaction data
4. Replace placeholder logic in monitor module
   - Update `poll_hub_events()` with real API calls
   - Update `poll_connected_events()` with real API calls
   - Implement proper event parsing

**Files to Create**: `trusted-verifier/src/aptos_client.rs`  
**Files to Modify**: `trusted-verifier/src/monitor/mod.rs`

---

### Phase 5: Core Monitoring & Validation Logic

**Goal**: Implement the actual business logic for cross-chain validation

**Tasks**:

1. Implement event monitoring loop
   - Start background monitoring for both chains
   - Poll for new events at regular intervals
   - Cache events in memory
   - Handle event deduplication
2. Implement validation logic
   - Cross-reference intent events from hub with escrow events
   - Validate deposit amounts match intent requirements
   - Check metadata matches (asset types, recipients)
   - Verify timing constraints (timeouts)
3. Implement approval/rejection workflow
   - Generate approval signatures for valid fulfillments
   - Generate rejection signatures for invalid fulfillments
   - Store signatures in cache
4. Connect monitoring to API endpoints
   - Expose monitoring status via API
   - Provide cached events via API
   - Allow manual trigger of validation

**Files to Modify**: `trusted-verifier/src/monitor/mod.rs`, `trusted-verifier/src/validator/mod.rs`

---

### Phase 6: Comprehensive Testing

**Goal**: Ensure reliability and correctness

**Tasks**:

1. Add unit tests
   - Test crypto operations
   - Test configuration loading
   - Test API endpoints
2. Add integration tests
   - Test against local Aptos chains
   - Test full workflow (intent → escrow → validation)
   - Test error handling
3. Add end-to-end tests
   - Test complete cross-chain scenarios
   - Test with multiple intents
   - Test timeout scenarios
4. Performance testing
   - Load testing the API
   - Stress testing event monitoring
   - Memory usage monitoring

**Files to Create**: `trusted-verifier/tests/integration_test.rs`  
**Files to Modify**: Add tests to all modules

---

## 🎯 Priority Order

**Recommended Sequence**:

1. ~~**Phase 3** (Local Testing Environment)~~ **COMPLETED** ✅
   - Real chains running
   - Contracts deployed
   - Baseline established
2. **Phase 4** (Aptos REST Client) - **NEXT**
   - Implement blockchain communication
   - Make real API calls
3. **Phase 5** (Core Logic)
   - Implement actual validation
   - Complete the workflow
4. **Phase 6** (Testing)
   - Ensure everything works
   - Add comprehensive test coverage

## 📝 Notes

- **Current Status**: Phase 3 complete - chains running, config loaded, verifier starts successfully
- **Chains**: Dual Docker chains on ports 8080 (Hub) and 8082 (Connected)
- **Deployed Modules**: Both chains have aptos_intent modules deployed
- **Configuration**: `trusted-verifier/config/verifier.toml` contains real addresses and keys
- **Verifier**: Running on port 3000, API endpoints functional
- **Next Step**: Phase 4 - Implement actual blockchain communication
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
