# Unit Test Coverage Comparison

## Overview

This document compares unit test coverage in two areas:
1. **Contract-level unit tests**: EVM contracts vs Aptos Move contracts
2. **Verifier service unit tests**: EVM functionality vs Aptos functionality in trusted-verifier

---

## Part 1: Contract Unit Tests Comparison

### Aptos Move Tests (`move-intent-framework/tests/`)

**Test Files:**
1. ✅ `intent_tests.move` - Core intent framework tests
2. ✅ `fa_tests.move` - Fungible asset trading tests
3. ✅ `intent_reservation_tests.move` - Reservation system tests
4. ✅ `fa_intent_with_oracle_tests.move` - Oracle-based intent tests
5. ✅ `fa_entryflow_tests.move` - Complete intent flow tests
6. ✅ `intent_as_escrow_tests.move` - Escrow intent tests
7. ✅ `fa_intent_cross_chain_tests.move` - Cross-chain intent tests
8. ✅ `fa_test_utils.move` - Shared test helper functions

**Total: 8 test files**

### EVM Tests (`evm-intent-framework/test/`)

**Test Files:**
1. ✅ `IntentEscrow.test.js` - IntentEscrow contract tests

**Total: 1 test file, ~13 test cases**

### Contract Test Coverage Gaps

**EVM is missing:**
- Cross-chain intent ID conversion tests
- Expiry handling tests
- Comprehensive error condition tests
- Edge case tests (max values, empty deposits, etc.)
- Integration tests for multiple escrows
- Event emission comprehensive tests

---

## Part 2: Verifier Service Unit Tests Comparison

### Current Test Files (`trusted-verifier/tests/`)

1. ✅ `crypto_tests.rs` - 9 tests for cryptographic operations
2. ✅ `config_tests.rs` - 4 tests for configuration management
3. ✅ `monitor_tests.rs` - 3 tests for event monitoring
4. ✅ `cross_chain_tests.rs` - 1 test for cross-chain matching

**Total: 17 unit tests**

### Verifier Test Coverage Analysis

#### Crypto Tests (`crypto_tests.rs`)

**Aptos Coverage (Ed25519):**
- ✅ `test_unique_key_generation()` - Key pair generation
- ✅ `test_signature_creation_and_verification()` - Ed25519 signature creation/verification
- ✅ `test_signature_verification_fails_for_wrong_message()` - Signature validation
- ✅ `test_approval_and_rejection_signatures_differ()` - Approval vs rejection
- ✅ `test_escrow_approval_signature()` - Escrow approval signatures
- ✅ `test_public_key_consistency()` - Public key consistency
- ✅ `test_signature_contains_timestamp()` - Timestamp validation
- ✅ `test_approval_value_true()` - Approval value (1)
- ✅ `test_approval_value_false()` - Rejection value (0)

**EVM Coverage (ECDSA):**
- ❌ **MISSING** - No test for `create_evm_approval_signature()`
- ❌ **MISSING** - No test for ECDSA signature verification
- ❌ **MISSING** - No test for `get_ethereum_address()` derivation
- ❌ **MISSING** - No test for ECDSA key derivation from Ed25519
- ❌ **MISSING** - No test for EVM signature format (r || s || v, 65 bytes)
- ❌ **MISSING** - No test for keccak256 hashing in EVM signatures
- ❌ **MISSING** - No test for Ethereum signed message format

#### Config Tests (`config_tests.rs`)

**Aptos Coverage:**
- ✅ `test_default_config_creation()` - Default config structure
- ✅ `test_known_accounts_field()` - Known accounts field (None)
- ✅ `test_known_accounts_with_values()` - Known accounts with values
- ✅ `test_config_serialization()` - TOML serialization/deserialization

**EVM Coverage:**
- ❌ **MISSING** - No test for `EvmChainConfig` structure
- ❌ **MISSING** - No test for EVM chain config loading
- ❌ **MISSING** - No test for EVM chain config serialization
- ❌ **MISSING** - No test for optional `connected_chain_evm` field in Config
- ❌ **MISSING** - No test for EVM config with escrow_contract_address, chain_id, verifier_address

#### Monitor Tests (`monitor_tests.rs`)

**Aptos Coverage:**
- ✅ `test_revocable_intent_rejection()` - Revocable intent validation
- ✅ `test_generates_approval_when_fulfillment_and_escrow_present()` - Approval generation
- ✅ `test_returns_error_when_no_matching_escrow()` - Error handling

**EVM Coverage:**
- ❌ **MISSING** - No test for EVM escrow detection logic
- ❌ **MISSING** - No test for ECDSA signature creation for EVM escrows
- ❌ **MISSING** - No test for EVM vs Aptos escrow differentiation
- ❌ **MISSING** - No test for EVM escrow approval flow

#### Cross-Chain Tests (`cross_chain_tests.rs`)

**Aptos Coverage:**
- ✅ `test_cross_chain_intent_matching()` - Intent ID matching between chains

**EVM Coverage:**
- ❌ **MISSING** - No test for cross-chain matching with EVM escrows
- ❌ **MISSING** - No test for intent_id conversion to EVM format
- ❌ **MISSING** - No test for EVM escrow matching with hub intents

### Verifier Test Coverage Summary

**Missing EVM Unit Tests:**
- **Crypto Tests:** ~9 tests for ECDSA/EVM signatures
- **Config Tests:** ~5 tests for EVM chain configuration
- **Monitor Tests:** ~5 tests for EVM escrow handling
- **Cross-Chain Tests:** ~3 tests for EVM cross-chain matching

**Total: ~22 missing unit tests for EVM functionality in trusted-verifier**

---

## Overall Summary

### Contract-Level Tests
- **Aptos:** 8 test files, comprehensive coverage
- **EVM:** 1 test file, ~13 test cases
- **Gap:** Significant missing coverage in EVM contract tests

### Verifier Service Tests
- **Aptos functionality:** 17 tests, comprehensive coverage
- **EVM functionality:** 0 tests
- **Gap:** All EVM functionality in verifier is untested

### Impact
- EVM contracts have significantly less unit test coverage than Aptos contracts
- EVM verifier functionality has no unit test coverage
- Reduced confidence in EVM integration compared to Aptos

---

## Part 3: Detailed Test Implementation Plans

### EVM Contract Unit Test Implementation Plan

Based on analysis from Task 1.1 and planning from Task 1.3, the following test cases need to be added to `evm-intent-framework/test/IntentEscrow.test.js`:

#### 1. Expiry Handling Tests (3 tests)
- `test_expired_escrow_cancellation_allowed` - Verify maker can cancel expired escrow
- `test_expired_escrow_claim_prevention` - Verify claim fails for expired escrow (if enforced)
- `test_expiry_timestamp_validation` - Verify expiry timestamp is stored correctly

#### 2. Cross-Chain Intent ID Conversion Tests (4 tests)
- `test_aptos_hex_to_evm_uint256_conversion` - Convert Aptos hex intent ID to EVM uint256
- `test_intent_id_boundary_values` - Test max uint256, zero, and edge values
- `test_invalid_hex_format_handling` - Test invalid hex strings, non-hex characters
- `test_intent_id_zero_padding` - Test left-padding for shorter intent IDs

#### 3. Error Condition Tests (8 tests)
- `test_zero_amount_deposit_revert` - Verify deposit with 0 amount reverts
- `test_invalid_token_address_handling` - Test address(0) and invalid addresses
- `test_non_existent_escrow_operations` - Test operations on uninitialized escrows
- `test_unauthorized_maker_operations` - Test maker-only operations from other addresses
- `test_invalid_signature_format` - Test malformed signatures (wrong length, invalid v)
- `test_eth_token_deposit_mismatch` - Test ETH sent to token escrow and vice versa
- `test_insufficient_erc20_allowance` - Test deposit with insufficient token allowance
- `test_reentrancy_protection` - Test reentrancy attack scenarios

#### 4. Edge Case Tests (5 tests)
- `test_maximum_uint256_values` - Test with max uint256 for amounts and intent IDs
- `test_empty_deposit_scenarios` - Test escrow with zero balance edge cases
- `test_multiple_escrows_per_maker` - Test maker creating multiple escrows
- `test_gas_limit_scenarios` - Test gas consumption for large operations
- `test_concurrent_operations` - Test multiple simultaneous escrow operations

#### 5. Integration Tests (4 tests)
- `test_complete_deposit_to_claim_workflow` - Full workflow from init to claim
- `test_multi_token_scenarios` - Test with different ERC20 tokens
- `test_comprehensive_event_emission` - Verify all events with correct parameters
- `test_complete_cancellation_workflow` - Full workflow from init to cancel

**Total: ~24 new test cases**

**Test Helper Functions Needed:**
- `hexToUint256(hexString)` - Convert Aptos hex intent ID to EVM uint256
- `advanceTime(seconds)` - Advance blockchain time for expiry testing
- `createExpiredEscrow(intentId, token, expiry)` - Helper to create expired escrow

---

### EVM Verifier Service Unit Test Implementation Plan

Based on analysis from Task 1.2 and planning from Task 1.4, the following test functions need to be added to `trusted-verifier/tests/`:

#### crypto_tests.rs - ECDSA Tests (9 tests)

1. `test_create_evm_approval_signature_success` - Verify ECDSA signature creation succeeds
2. `test_create_evm_approval_signature_format_65_bytes` - Verify signature is exactly 65 bytes (r || s || v)
3. `test_create_evm_approval_signature_verification` - Verify signature can be verified on-chain
4. `test_get_ethereum_address_derivation` - Verify Ethereum address derivation from ECDSA key
5. `test_evm_signature_recovery_id_calculation` - Verify recovery ID (v) is 27 or 28
6. `test_evm_signature_keccak256_hashing` - Verify keccak256 hashing in message preparation
7. `test_evm_signature_ethereum_message_prefix` - Verify Ethereum signed message format
8. `test_evm_intent_id_padding` - Verify intent ID padding to 32 bytes
9. `test_evm_signature_invalid_intent_id` - Verify error handling for invalid intent IDs

#### config_tests.rs - EVM Config Tests (5 tests)

1. `test_evm_chain_config_structure` - Verify EvmChainConfig struct fields
2. `test_evm_chain_config_serialization` - Verify TOML serialization/deserialization
3. `test_config_with_evm_chain_optional` - Verify optional connected_chain_evm field in Config
4. `test_evm_chain_config_with_all_fields` - Verify all fields (rpc_url, escrow_contract_address, chain_id, verifier_address)
5. `test_evm_chain_config_defaults` - Verify default values if applicable

#### monitor_tests.rs - EVM Escrow Tests (5 tests)

1. `test_evm_escrow_detection_logic` - Verify EVM escrow detection (chain type check)
2. `test_evm_escrow_ecdsa_signature_creation` - Verify ECDSA signature creation for EVM escrows
3. `test_evm_vs_aptos_escrow_differentiation` - Verify correct signature type based on chain
4. `test_evm_escrow_approval_flow` - Verify complete EVM escrow approval workflow
5. `test_evm_escrow_with_invalid_intent_id` - Verify error handling for invalid intent IDs

#### cross_chain_tests.rs - EVM Cross-Chain Tests (3 tests)

1. `test_evm_escrow_cross_chain_matching` - Verify EVM escrow matches hub intent
2. `test_intent_id_conversion_to_evm_format` - Verify intent ID format conversion
3. `test_evm_escrow_matching_with_aptos_hub_intent` - Verify cross-chain matching logic

**Total: ~22 new test functions**

**Test Helper Functions Needed:**
- `build_test_config_with_evm()` - Create test config with EVM chain configuration
- `create_mock_evm_escrow_event()` - Create mock EVM escrow event for testing

---

## Part 4: Implementation Priority and Effort Estimates

### Priority 1: Critical Security Tests (Implement First)
- EVM signature verification tests (crypto_tests.rs)
- Error condition tests (IntentEscrow.test.js)
- EVM escrow detection and approval flow (monitor_tests.rs)

**Estimated Effort:** 2-3 days

### Priority 2: Core Functionality Tests
- Expiry handling tests (IntentEscrow.test.js)
- EVM config tests (config_tests.rs)
- Cross-chain matching tests (cross_chain_tests.rs)

**Estimated Effort:** 2-3 days

### Priority 3: Edge Cases and Integration Tests
- Edge case tests (IntentEscrow.test.js)
- Integration tests (IntentEscrow.test.js)
- Comprehensive event emission tests

**Estimated Effort:** 1-2 days

### Total Estimated Effort: 5-8 days

---

---

## Part 5: Test Implementation Specification

### 5.1 Test File Organization and Structure

#### EVM Contract Tests (JavaScript/TypeScript)

**File Structure:**
```
evm-intent-framework/
├── test/
│   ├── IntentEscrow.test.js          # Main test file (existing + new tests)
│   └── helpers/
│       ├── testHelpers.js           # Shared test utilities
│       └── mockData.js               # Mock data generators
```

**Test Organization in `IntentEscrow.test.js`:**
- Follow existing structure with `describe` blocks for each category
- Use nested `describe` blocks for related test groups
- Maintain consistent naming: `describe("Category", function() { ... })`

**Structure:**
```javascript
describe("IntentEscrow", function() {
  // Shared setup in beforeEach
  
  describe("Initialization", function() { ... });      // Existing
  describe("Deposit", function() { ... });              // Existing
  describe("Claim", function() { ... });                // Existing
  describe("Cancel", function() { ... });               // Existing
  
  // New test categories:
  describe("Expiry Handling", function() { ... });      // New: 3 tests
  describe("Cross-Chain Intent ID Conversion", function() { ... }); // New: 4 tests
  describe("Error Conditions", function() { ... });     // New: 8 tests
  describe("Edge Cases", function() { ... });          // New: 5 tests
  describe("Integration", function() { ... });          // New: 4 tests
});
```

#### Verifier Service Tests (Rust)

**File Structure:**
```
trusted-verifier/
├── tests/
│   ├── mod.rs                        # Test helpers (existing)
│   ├── crypto_tests.rs               # Crypto tests (existing + 9 new ECDSA tests)
│   ├── config_tests.rs               # Config tests (existing + 5 new EVM tests)
│   ├── monitor_tests.rs               # Monitor tests (existing + 5 new EVM tests)
│   └── cross_chain_tests.rs          # Cross-chain tests (existing + 3 new EVM tests)
```

**Test Organization:**
- Add new test functions to existing files
- Group EVM tests in separate sections with comments
- Follow existing naming: `test_<functionality>_<scenario>()`
- Use `#[test]` for synchronous tests, `#[tokio::test]` for async tests

**Structure in each file:**
```rust
// Existing Aptos tests...

// ============================================================================
// EVM-SPECIFIC TESTS
// ============================================================================

#[test]
fn test_create_evm_approval_signature_success() { ... }

// ... additional EVM tests
```

---

### 5.2 Test Data Requirements and Mock Setup Procedures

#### EVM Contract Tests

**Mock Setup (in `beforeEach`):**
```javascript
beforeEach(async function() {
  // Get signers
  [verifier, maker, solver, other] = await ethers.getSigners();
  
  // Deploy mock ERC20 token
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  token = await MockERC20.deploy("Test Token", "TEST");
  await token.waitForDeployment();
  
  // Deploy escrow
  const IntentEscrow = await ethers.getContractFactory("IntentEscrow");
  escrow = await IntentEscrow.deploy(verifier.address);
  await escrow.waitForDeployment();
  
  // Default intent ID
  intentId = ethers.parseUnits("1", 0);
});
```

**Test Helper Functions (create `test/helpers/testHelpers.js`):**
```javascript
// Convert Aptos hex intent ID to EVM uint256
function hexToUint256(hexString) {
  // Remove 0x prefix if present
  const hex = hexString.startsWith('0x') ? hexString.slice(2) : hexString;
  // Convert to BigInt, pad to 32 bytes if needed
  return BigInt('0x' + hex.padStart(64, '0'));
}

// Advance blockchain time for expiry testing
async function advanceTime(seconds) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}

// Create expired escrow helper
async function createExpiredEscrow(escrow, maker, intentId, token, expiryOffset = -3600) {
  const expiry = Math.floor(Date.now() / 1000) + expiryOffset; // Negative = expired
  await escrow.connect(maker).createEscrow(intentId, token.target, amount);
  // Advance time to make it expired
  await advanceTime(Math.abs(expiryOffset) + 1);
  return expiry;
}
```

**Mock Data Requirements:**
- **Intent IDs:** Use various formats (hex strings, uint256, edge values)
- **Token Amounts:** Standard amounts (100 ETH), max uint256, zero, small values
- **Addresses:** Valid addresses, address(0), different signers
- **Timestamps:** Current time, expired, far future
- **Signatures:** Valid ECDSA signatures, invalid formats, wrong signers

#### Verifier Service Tests

**Test Helper Functions (add to `tests/mod.rs`):**
```rust
/// Build test config with EVM chain configuration
pub fn build_test_config_with_evm() -> Config {
    let mut config = build_test_config();
    config.connected_chain_evm = Some(EvmChainConfig {
        rpc_url: "http://127.0.0.1:8545".to_string(),
        escrow_contract_address: "0x1234567890123456789012345678901234567890".to_string(),
        chain_id: 31337,
        verifier_address: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd".to_string(),
    });
    config
}

/// Create mock EVM escrow event for testing
pub fn create_mock_evm_escrow_event() -> EscrowEvent {
    EscrowEvent {
        chain: "evm".to_string(),
        escrow_id: "0xescrow123".to_string(),
        intent_id: "0xintent456".to_string(),
        issuer: "0xissuer789".to_string(),
        source_metadata: "{}".to_string(),
        source_amount: 1000,
        desired_metadata: "{}".to_string(),
        desired_amount: 1000,
        expiry_time: 9999999999,
        revocable: false,
        timestamp: 1,
    }
}
```

**Mock Data Requirements:**
- **ECDSA Keys:** Generate fresh keys for each test using `k256::ecdsa::SigningKey::random()`
- **Intent IDs:** Hex strings with/without 0x prefix, various lengths (1-32 bytes)
- **Config Values:** Valid EVM chain configs, optional fields, serialization round-trips
- **Events:** Mock escrow events, fulfillment events, intent events

---

### 5.3 Test Execution Order and Dependencies

#### EVM Contract Tests

**Execution Order:**
1. **Initialization tests** (no dependencies)
2. **Deposit tests** (depends on: initialization)
3. **Expiry handling tests** (depends on: initialization, deposit)
4. **Error condition tests** (can run independently, various setups)
5. **Cross-chain intent ID tests** (can run independently)
6. **Edge case tests** (depends on: basic functionality)
7. **Claim tests** (depends on: initialization, deposit)
8. **Cancel tests** (depends on: initialization, deposit)
9. **Integration tests** (depends on: all above)

**Test Isolation:**
- Each test should be independent (use `beforeEach` for fresh state)
- No shared state between tests
- Use unique intent IDs when needed: `intentId + BigInt(testIndex)`

#### Verifier Service Tests

**Execution Order:**
1. **Config tests** (no dependencies, can run first)
2. **Crypto tests** (no dependencies, can run in parallel)
3. **Monitor tests** (depends on: crypto for signature creation)
4. **Cross-chain tests** (depends on: crypto, config, monitor)

**Test Isolation:**
- Each test creates its own `CryptoService` instance
- Use `build_test_config()` or `build_test_config_with_evm()` for fresh configs
- No shared mutable state between tests

**Parallel Execution:**
- Rust tests run in parallel by default (`cargo test`)
- JavaScript tests run sequentially by default (Hardhat)
- Both are safe for parallel execution due to test isolation

---

### 5.4 Coverage Metrics and Success Criteria

#### Coverage Targets

**EVM Contract Tests:**
- **Line Coverage:** ≥ 90% for `IntentEscrow.sol`
- **Branch Coverage:** ≥ 85% (all code paths tested)
- **Function Coverage:** 100% (all public/external functions)
- **Event Coverage:** 100% (all events emitted and verified)

**Verifier Service Tests:**
- **Line Coverage:** ≥ 85% for EVM-related code paths
- **Function Coverage:** 100% for all EVM-specific functions:
  - `create_evm_approval_signature()`
  - `get_ethereum_address()`
  - EVM config loading/serialization
  - EVM escrow detection and approval

#### Success Criteria by Category

**Priority 1: Critical Security Tests**
- ✅ All ECDSA signature tests pass
- ✅ All error condition tests pass
- ✅ All EVM escrow approval flow tests pass
- ✅ No security vulnerabilities identified

**Priority 2: Core Functionality Tests**
- ✅ All expiry handling tests pass
- ✅ All EVM config tests pass
- ✅ All cross-chain matching tests pass
- ✅ Config serialization/deserialization works correctly

**Priority 3: Edge Cases and Integration Tests**
- ✅ All edge case tests pass
- ✅ All integration tests pass
- ✅ Event emission verified for all scenarios
- ✅ Gas usage within acceptable limits

#### Overall Test Suite Completion Criteria

**Before marking Task 3 complete:**
1. All 24 EVM contract test cases pass
2. All 22 EVM verifier test functions pass
3. Coverage metrics meet targets (90%+ line coverage)
4. All tests pass in CI/CD pipeline
5. No flaky tests (100% pass rate over 10 runs)
6. Test execution time < 5 minutes for full suite

---

### 5.5 CI/CD Integration and Test Automation

#### Existing CI/CD Setup

**GitHub Actions Workflows:**

1. **EVM Unit Tests** (`.github/workflows/evm_tests.yml`):
   - Triggers: PR, push to main
   - Runs: `cd evm-intent-framework && npm test`
   - Environment: Ubuntu latest, Nix shell

2. **Rust Tests** (`.github/workflows/rust_tests.yml`):
   - Triggers: PR, push to main
   - Runs: `cd trusted-verifier && cargo test`
   - Environment: Ubuntu latest, Nix shell

#### Integration Requirements

**EVM Contract Tests:**
- Tests automatically run on PR creation/update
- Must pass before merge
- Use existing `npm test` command (Hardhat test runner)
- No additional CI configuration needed

**Verifier Service Tests:**
- Tests automatically run via `cargo test`
- Must pass before merge
- New EVM tests will run automatically with existing Rust test suite
- No additional CI configuration needed

#### Test Automation

**Local Development:**
```bash
# Run EVM contract tests
cd evm-intent-framework && npm test

# Run specific test file
cd evm-intent-framework && npx hardhat test test/IntentEscrow.test.js

# Run verifier service tests
cd trusted-verifier && cargo test

# Run specific test module
cd trusted-verifier && cargo test crypto_tests

# Run with coverage (if configured)
cd evm-intent-framework && npx hardhat coverage
cd trusted-verifier && cargo tarpaulin
```

**CI/CD Pipeline:**
- Tests run automatically on every PR
- Results reported in GitHub Actions
- Failures block merge
- Coverage reports can be added to PR comments (optional)

#### Pre-commit Hooks (Optional Enhancement)

Consider adding pre-commit hooks:
```bash
# .git/hooks/pre-commit
#!/bin/bash
cd evm-intent-framework && npm test
cd ../trusted-verifier && cargo test
```

---

### 5.6 Test Maintenance Guidelines

#### Adding New Tests

**When to Add Tests:**
- New functionality added to `IntentEscrow.sol`
- New EVM features in verifier service
- Bug fixes (add regression test)
- Edge cases discovered in production

**How to Add Tests:**
1. Follow existing test structure and naming conventions
2. Add to appropriate `describe` block or test file
3. Use existing helper functions when possible
4. Ensure test is isolated (no shared state)
5. Update this document if adding new test categories

#### Updating Existing Tests

**When to Update Tests:**
- Contract interface changes (function signatures)
- Test helper function improvements
- Test data requirements change
- Performance optimizations

**Update Process:**
1. Identify affected tests
2. Update test code to match new interface
3. Verify all tests still pass
4. Update documentation if test structure changes

#### Test Maintenance Checklist

**Before Each Release:**
- [ ] All tests pass locally
- [ ] All tests pass in CI/CD
- [ ] Coverage metrics meet targets
- [ ] No flaky tests identified
- [ ] Test execution time acceptable
- [ ] Documentation updated if needed

**Quarterly Review:**
- [ ] Review test coverage reports
- [ ] Identify untested code paths
- [ ] Remove obsolete tests
- [ ] Refactor duplicate test code
- [ ] Update test helpers for common patterns

#### Troubleshooting Common Issues

**EVM Contract Tests:**
- **Issue:** Tests failing due to time-dependent logic
  - **Solution:** Use `advanceTime()` helper, mock timestamps
- **Issue:** Non-deterministic test failures
  - **Solution:** Ensure unique intent IDs, reset state in `beforeEach`
- **Issue:** Gas limit errors
  - **Solution:** Optimize test setup, reduce test data size

**Verifier Service Tests:**
- **Issue:** Tests failing due to key generation
  - **Solution:** Use `build_test_config()` for fresh keys each test
- **Issue:** Async test timeouts
  - **Solution:** Increase timeout, check for deadlocks
- **Issue:** Config serialization failures
  - **Solution:** Verify TOML format, check optional fields

---

## Summary

This document provides a comprehensive comparison of unit test coverage between Aptos and EVM implementations, identifies all gaps, and provides detailed implementation plans for both contract-level and verifier service unit tests. The plans are ready for implementation in Task 3.

**Part 5 (Test Implementation Specification)** provides:
- Complete test file organization and structure
- Detailed mock setup procedures and helper functions
- Test execution order and dependency management
- Coverage metrics and success criteria
- CI/CD integration details
- Test maintenance guidelines

All sections are now documented and ready for Task 3 implementation.
