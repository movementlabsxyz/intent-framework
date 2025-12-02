# Test Analysis & Recommendations for Negotiation Routing

## Existing Test Patterns

### Test Organization
1. **All Tests**: Located in `tests/` directory (integration tests)
   - Example: `tests/monitor_tests.rs`, `tests/mvm/crypto_tests.rs`
   - Use `#[path = "mod.rs"] mod test_helpers;` to import helpers
   - Tests are NOT co-located with source code

2. **Note**: Some source files have empty `#[cfg(test)]` modules as placeholders
   - Example: `trusted-verifier/src/mvm_client.rs` has `#[cfg(test)] mod tests { // Tests will be added in integration tests }`
   - These are just placeholders, not actual tests
   - **Exception**: `trusted-verifier/src/storage/draft_intents.rs` has actual unit tests (newly added)

### Test Style Patterns

1. **Test Naming**: `test_<what_is_tested>` (descriptive, lowercase with underscores)
   - Example: `test_normalize_intent_id_leading_zeros`
   - Example: `test_fcfs_signature`

2. **Test Documentation**: Tests include comments explaining "Why"
   ```rust
   /// Test that normalize_intent_id handles leading zeros correctly
   /// What is tested: Intent IDs with leading zeros are normalized to match those without
   /// Why: EVM and Move VM may format the same intent_id differently (with/without leading zeros)
   #[test]
   fn test_normalize_intent_id_leading_zeros() { ... }
   ```

3. **Test Structure**:
   - Section comments group related tests: `// ============================================================================`
   - Helper functions defined at top of test module
   - Use `assert!`, `assert_eq!`, `assert_ne!` with descriptive error messages
   - Use `#[tokio::test]` for async tests, `#[test]` for sync tests

4. **Test Data**: Use helper functions from `tests/helpers.rs`
   - `build_test_config_with_mvm()` - Creates test config
   - `create_base_*()` - Creates base test data structures
   - Can be customized using Rust's struct update syntax: `..create_base_*()`

5. **Test Coverage**:
   - Positive cases (happy path)
   - Negative cases (error conditions)
   - Edge cases (boundary conditions)
   - Security cases (critical checks)

---

## Current Test Status

### ✅ Already Implemented (in `draft_intents.rs`)

1. **`test_add_and_get_draft`** ✅
   - Tests basic CRUD: add draft, retrieve by ID
   - Verifies draft fields are stored correctly

2. **`test_get_pending_drafts`** ✅
   - Tests retrieving all pending drafts
   - Verifies multiple drafts are returned

3. **`test_fcfs_signature`** ✅
   - Tests FCFS logic: first signature succeeds, second fails
   - Verifies first signature is stored correctly

### ❌ Missing Tests

#### Storage Module (`draft_intents.rs` or `tests/storage_tests.rs`) - Tests

**Edge Cases:**
- [ ] Test getting non-existent draft (should return None)
- [ ] Test expiry handling (drafts expire after expiry_time)
- [ ] Test `cleanup_expired()` marks expired drafts correctly
- [ ] Test expired drafts are excluded from `get_pending_drafts()`
- [ ] Test adding signature to non-existent draft (should error)
- [ ] Test adding signature to expired draft (should error)
- [ ] Test adding signature to already-signed draft (should error - FCFS)
- [ ] Test concurrent access (multiple readers/writers)

**Status Transitions:**
- [ ] Test draft status transitions: Pending → Signed
- [ ] Test draft status transitions: Pending → Expired
- [ ] Test signed draft cannot transition back to Pending

**Data Validation:**
- [ ] Test draft with empty draft_data (should work)
- [ ] Test draft with complex nested draft_data (should work)
- [ ] Test signature storage (all fields present)
- [ ] Test signature timestamp is set correctly

**Boundary Conditions:**
- [ ] Test expiry_time exactly at current time (edge case)
- [ ] Test expiry_time in the past (should be expired immediately)
- [ ] Test expiry_time far in future (should be valid)

#### API Module (`tests/negotiation_api_tests.rs`) - Integration Tests

**POST /draft-intent Handler:**
- [ ] Test successful draft creation
- [ ] Test draft_id is UUID format
- [ ] Test response structure matches expected format
- [ ] Test draft_data is stored correctly
- [ ] Test expiry_time is stored correctly
- [ ] Test requester_address is stored correctly
- [ ] Test invalid JSON in draft_data (should handle gracefully)
- [ ] Test missing required fields (should error)

**GET /draft-intent/:id Handler:**
- [ ] Test retrieving existing draft
- [ ] Test retrieving non-existent draft (should return 404)
- [ ] Test response includes all required fields
- [ ] Test status field is correct (pending/signed/expired)
- [ ] Test expired draft returns correct status

**GET /draft-intents/pending Handler:**
- [ ] Test returns all pending drafts
- [ ] Test excludes expired drafts
- [ ] Test excludes signed drafts
- [ ] Test excludes expired drafts
- [ ] Test empty list when no pending drafts
- [ ] Test response format matches expected structure
- [ ] Test draft_data is included in response

#### Integration Tests (`tests/negotiation_tests.rs`) - New File

**End-to-End API Tests:**
- [ ] Test full flow: POST draft → GET draft → GET /pending → POST signature → GET /signature
- [ ] Test multiple solvers polling same draft
- [ ] Test FCFS: first solver wins, second gets 409
- [ ] Test requester polls for signature (202 → 200)
- [ ] Test draft expiry (draft expires, no longer in pending list)

**Concurrent Access:**
- [ ] Test multiple requesters submitting drafts concurrently
- [ ] Test multiple solvers submitting signatures concurrently (FCFS)
- [ ] Test requester polling while solver submits signature

**Error Cases:**
- [ ] Test invalid draft_id format (should return 404)
- [ ] Test malformed request body (should return 400)
- [ ] Test missing required fields (should return 400)

---

## Recommended Test Implementation Plan

### Phase 1: Complete Storage Tests (Priority: High)
**Option A**: Keep unit tests in `trusted-verifier/src/storage/draft_intents.rs` (current approach)
- Add more tests to existing `#[cfg(test)]` module
- Edge cases (non-existent draft, expiry handling)
- Status transitions
- Boundary conditions

**Option B**: Move to `trusted-verifier/tests/storage_tests.rs` (matches codebase pattern)
- Move existing tests from `draft_intents.rs` to `tests/storage_tests.rs`
- Add additional tests following existing test patterns
- Use helpers from `tests/helpers.rs`

### Phase 2: Add API Handler Tests (Priority: Medium)
**File**: `trusted-verifier/tests/negotiation_api_tests.rs` (new)

Add integration tests for API handlers:
1. Mock store setup helpers
2. Tests for each handler function
3. Error case tests
4. Use Warp test framework or HTTP client to test endpoints

### Phase 3: Add Integration Tests (Priority: Medium)
**File**: `trusted-verifier/tests/negotiation_tests.rs` (new)

Add integration tests:
1. Full negotiation flow
2. Concurrent access scenarios
3. Error handling

### Phase 4: Add Helper Functions (Priority: Low)
**File**: `trusted-verifier/tests/helpers.rs`

Add helpers:
- `create_base_draft_intent_request()` - Creates test draft request
- `create_base_draft_intent()` - Creates test draft intent
- `create_base_draft_signature()` - Creates test signature

---

## Test Helper Functions Needed

### In `tests/helpers.rs`:

```rust
/// Create a base draft intent request with default test values.
pub fn create_base_draft_intent_request() -> DraftIntentRequest {
    DraftIntentRequest {
        requester_address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        draft_data: serde_json::json!({
            "offered_metadata": "0x1::test::Token",
            "offered_amount": 1000,
            "desired_metadata": "0x1::test::Token2",
            "desired_amount": 2000,
            "offered_chain_id": 1,
            "desired_chain_id": 2,
        }),
        expiry_time: 9999999999,
    }
}

/// Create a base draft intent with default test values.
pub fn create_base_draft_intent() -> DraftIntent {
    DraftIntent {
        draft_id: "test-draft-1".to_string(),
        requester_address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        draft_data: serde_json::json!({}),
        status: DraftIntentStatus::Pending,
        timestamp: 1000000,
        expiry_time: 9999999999,
        signature: None,
    }
}
```

---

## Test Coverage Goals

### Storage Module (`draft_intents.rs`)
- **Target**: 90%+ coverage
- **Critical Paths**: All public methods
- **Edge Cases**: Expiry, FCFS, concurrent access

### API Module (`negotiation.rs`)
- **Target**: 80%+ coverage
- **Critical Paths**: All handler functions
- **Error Cases**: Invalid input, missing data

### Integration Tests
- **Target**: Full flow coverage
- **Scenarios**: Happy path, FCFS, expiry, errors

---

## Example Test Template

```rust
/// Test that <what is tested>
/// What is tested: <specific behavior>
/// Why: <business reason>
#[tokio::test]
async fn test_<descriptive_name>() {
    // Arrange
    let store = DraftIntentStore::new();
    // ... setup test data
    
    // Act
    let result = store.<method>().await;
    
    // Assert
    assert!(result.is_ok(), "Should succeed");
    // ... more assertions
}
```

---

## Next Steps

1. **Immediate**: Add missing unit tests to `draft_intents.rs`
2. **Short-term**: Add unit tests to `negotiation.rs`
3. **Medium-term**: Create integration tests in `tests/negotiation_tests.rs`
4. **Long-term**: Add helper functions to `tests/helpers.rs`

