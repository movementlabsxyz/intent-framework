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

### ✅ Already Implemented

#### Storage Module (`tests/storage_tests.rs`) ✅

1. **CRUD Tests:**
   - ✅ `test_add_and_get_draft` - Basic CRUD operations
   - ✅ `test_get_nonexistent_draft` - Getting non-existent draft returns None
   - ✅ `test_get_pending_drafts` - Retrieve all pending drafts
   - ✅ `test_pending_drafts_exclude_expired` - Expired drafts excluded from pending list
   - ✅ `test_pending_drafts_exclude_signed` - Signed drafts excluded from pending list

2. **FCFS Signature Tests:**
   - ✅ `test_fcfs_first_signature_succeeds` - First signature succeeds
   - ✅ `test_fcfs_second_signature_fails` - Second signature fails (FCFS)
   - ✅ `test_signature_nonexistent_draft` - Adding signature to non-existent draft errors
   - ✅ `test_signature_expired_draft` - Adding signature to expired draft errors
   - ✅ `test_signature_timestamp` - Signature timestamp is set correctly

3. **Expiry Tests:**
   - ✅ `test_cleanup_expired` - Expired drafts are marked as expired correctly

4. **Status Transition Tests:**
   - ✅ `test_status_transition_pending_to_signed` - Status transitions Pending → Signed

5. **Data Validation Tests:**
   - ✅ `test_draft_with_empty_data` - Empty draft_data is handled correctly

#### Signature Validation (`tests/negotiation_validation_tests.rs`) ✅ NEW

1. **Signature Format Validation:**
   - ✅ `test_validate_signature_format_valid`
   - ✅ `test_validate_signature_format_wrong_length()`
   - ✅ `test_validate_signature_format_invalid_hex()`
   - ✅ `test_validate_signature_format_case_insensitive()`
   - ✅ `test_validate_signature_format_empty()`
   - ✅ `test_validate_signature_format_only_prefix()`

#### MVM Client (`tests/mvm_client_tests.rs`) ✅ NEW

1. **Solver Public Key Tests:**
   - ✅ `test_get_solver_public_key_success` - Returns public key when solver is registered
   - ✅ `test_get_solver_public_key_not_registered` - Returns None when solver not registered
   - ✅ `test_get_solver_public_key_empty_array` - Handles empty array response
   - ✅ `test_get_solver_public_key_ed25519_format` - Handles 32-byte Ed25519 public key

### ❌ Missing Tests

#### Storage Module (`tests/storage_tests.rs`)

**Edge Cases:**

- ✅ Test `cleanup_expired()` marks expired drafts correctly (`test_cleanup_expired`)
- [ ] Test concurrent access (multiple readers/writers) - Would require more complex test setup

**Data Validation:**

- ✅ Test draft with empty draft_data (`test_draft_with_empty_data`)
- [ ] Test draft with complex nested draft_data (should work)

**Boundary Conditions:**

- [ ] Test expiry_time exactly at current time (edge case)
- ✅ Test expiry_time in the past (`test_signature_expired_draft` uses `past_expiry_time()`)

#### API Module (`tests/negotiation_api_tests.rs`) - Integration Tests

**Note**: API handler tests are not implemented. The handlers are private and thin wrappers around the storage layer. The storage layer is comprehensively tested, and signature validation logic is tested separately. Integration tests would require mocking the warp framework or using HTTP client tests, which is more complex.

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

### Phase 1: Complete Storage Tests (Priority: High) ✅ COMPLETED

**Status**: Tests moved to `trusted-verifier/tests/storage_tests.rs` ✅

- Comprehensive storage tests implemented
- FCFS logic fully tested
- Expiry handling tested
- Status transitions tested
- Edge cases covered (non-existent draft, expired draft)

### Phase 2: Add Signature Validation Tests (Priority: High) ✅ COMPLETED

**File**: `trusted-verifier/tests/negotiation_validation_tests.rs` ✅

**Status**: Signature format validation tests implemented:

1. ✅ Valid signature format tests
2. ✅ Invalid format tests (wrong length, invalid hex)
3. ✅ Edge cases (empty, only prefix)
4. ✅ Case insensitivity tests

**File**: `trusted-verifier/tests/mvm_client_tests.rs` ✅

**Status**: Solver registration validation tests implemented:

1. ✅ `get_solver_public_key` tests (registered, not registered, edge cases)
2. ✅ Ed25519 format handling tests

### Phase 2b: Add API Handler Tests (Priority: Low) ⏸️ DEFERRED

**Note**: API handlers are private and thin wrappers. Storage layer is comprehensively tested. Integration tests would require HTTP client or warp mocking, which adds complexity. Deferred for now.

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

### In `tests/helpers.rs`

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
