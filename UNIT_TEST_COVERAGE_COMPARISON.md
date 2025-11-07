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
1. ✅ `IntentVault.test.js` - IntentVault contract tests

**Total: 1 test file, ~13 test cases**

### Contract Test Coverage Gaps

**EVM is missing:**
- Cross-chain intent ID conversion tests
- Expiry handling tests
- Comprehensive error condition tests
- Edge case tests (max values, empty deposits, etc.)
- Integration tests for multiple vaults
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
- ❌ **MISSING** - No test for optional `evm_chain` field in Config
- ❌ **MISSING** - No test for EVM config with vault_address, chain_id, verifier_address

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
- ❌ **MISSING** - No test for EVM escrow matching with Aptos hub intents

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
