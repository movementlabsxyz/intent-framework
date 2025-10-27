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

## 🚧 Next Steps

### Phase 3: Local Testing Environment (Recommended First)

**Goal**: Set up local Aptos chains for testing without deploying to mainnet

**Tasks**:

1. Run existing deployment script
   - Use `move-intent-framework/tests/cross_chain/setup-and-deploy.sh`
   - This script sets up dual chains AND deploys contracts automatically
   - Creates `intent-account-chain1` and `intent-account-chain2` profiles
2. Update verifier.toml with real module addresses
   - Get deployed module addresses from script output
   - Update `config/verifier.toml` with correct addresses
3. Test verifier connection to real chains
   - Verify health of both chains
   - Test basic API connectivity
   - Check event monitoring setup

**Files to Modify**: `trusted-verifier/config/verifier.toml`  
**Commands to Run**:

```bash
cd move-intent-framework/tests/cross_chain
./setup-and-deploy.sh
# This will output the addresses we need for verifier.toml
```

**Existing Script Details**:

- Location: `move-intent-framework/tests/cross_chain/setup-and-deploy.sh`
- What it does:
  1. Starts dual Docker chains (ports 8080 and 8082)
  2. Configures Aptos CLI profiles for both chains
  3. Deploys contracts to both chains automatically
  4. Outputs all addresses and useful commands

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

1. **Phase 3** (Local Testing Environment) - **START HERE**
   - Get real chains running
   - Deploy contracts
   - Establish baseline
2. **Phase 4** (Aptos REST Client)
   - Implement blockchain communication
   - Make real API calls
3. **Phase 5** (Core Logic)
   - Implement actual validation
   - Complete the workflow
4. **Phase 6** (Testing)
   - Ensure everything works
   - Add comprehensive test coverage

## 📝 Notes

- **Current Status**: API endpoints are functional but make no blockchain calls
- **Blocking Issue**: Need local chains to test against
- **Next Command**: Run `./infra/setup-docker/setup-dual-chains.sh`
- **Dependencies**: Docker must be running
- **Configuration**: Uses `trusted-verifier/config/verifier.toml`
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
