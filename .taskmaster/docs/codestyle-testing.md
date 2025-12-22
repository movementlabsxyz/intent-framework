# Test Refactoring Plan: Replace Magic Numbers with Constants

## Task Overview

Refactor test files in the `trusted-verifier` project to improve code quality by:

1. **Replacing magic numbers** (hardcoded literal values) with named constants
2. **Standardizing naming conventions** (e.g., using `_addr` suffix for addresses)
3. **Improving code readability and maintainability**

## Rules and Guidelines

### 1. Semantic Meaning Rule

**Each constant must represent a distinct concept.**

- ❌ **Don't reuse** `DUMMY_ESCROW_ID_MVM` for transaction hashes, even if the hex values happen to match
- ✅ **Create separate constants** for different concepts (e.g., `DUMMY_TX_HASH` for transaction hashes)
- **Rationale**: Different concepts may have different formats or meanings, even if values appear similar

### 2. Constant Naming Convention

**Use descriptive names that clearly indicate purpose and format:**

- `DUMMY_*_ADDR_*` for addresses (e.g., `DUMMY_SOLVER_ADDR_EVM`, `DUMMY_REQUESTER_ADDR_MVM_HUB`)
- `DUMMY_*_ID_*` for IDs (e.g., `DUMMY_INTENT_ID`, `DUMMY_ESCROW_ID_MVM`)
- `DUMMY_TX_HASH` for transaction hashes
- `DUMMY_EXPIRY` for timestamps
- `DUMMY_*_CONTRACT_ADDR_*` for contract addresses (e.g., `DUMMY_ESCROW_CONTRACT_ADDR_EVM`)

### 3. Hex Pattern Rule

Use unique repeating hex digit patterns in sequential order (0x1111..., 0x2222..., 0x3333..., etc.)

- Makes constants easily identifiable in test output and debugging

### 4. Variable Naming Convention

Standardize variable and parameter names:

- Address variables/parameters must use `_addr` suffix (e.g., `solver_addr`, `requester_addr`, `escrow_reserved_solver_addr`)
- Solver-related variables should use `solver_` prefix where appropriate (e.g., `solver_registered_evm_addr`)
- Avoid generic names like `address` or `addr` without context
- Use descriptive names: `registered_evm_address` → `solver_registered_evm_addr`

### 5. Code Quality Rule

Remove unnecessary variable bindings:

- ❌ **Don't use** `let` statements when the value is only used once
- ✅ **Inline values** directly into function calls
- ✅ **Keep `let`** when the variable is used multiple times or improves readability
- **Exception**: Test-specific identifiers (e.g., `0xwrong_solver`, `0xunregistered_solver`) MUST be inlined with descriptive comments

### 6. Adding New Constants Rule

Before adding a new constant, ask for approval:

- ❌ **Don't** create new dummy constants without explicit user approval
- ✅ **First** check if an existing constant can be reused (following Rule 1)
- ✅ **If new constant needed**, propose it to the user before adding
- ✅ **After approval**, add to `helpers.rs` and export via `mod.rs`

### 7. Test-Specific Identifiers

For test-specific values that aren't reusable constants:

- Use descriptive inline values with comments only when they add meaningful context (e.g., `"0xwrong_solver" // different solver address as registered` to explain why it's wrong)
- Don't add comments that just state the obvious (e.g., don't comment every test URL, profile name, or numeric value)
- Don't create constants for one-off test cases
- Only create constants for values used across multiple tests

### 8. Struct Update Syntax Pattern

Use Rust's struct update syntax with default helper functions to reduce duplication:

- ✅ **Use `..function_name()`** to fill remaining struct fields from default helper functions
- ✅ **Override only specific fields** that differ from the default
- ✅ **Create default helper functions** (e.g., `create_default_intent_mvm()`, `create_default_escrow_event()`) that return structs with sensible defaults
- ✅ **Chain default functions** when appropriate (e.g., `create_default_intent_evm()` can use `..create_default_intent_mvm()`)

**Example:**

```rust
let evm_escrow = EscrowEvent {
    intent_id: hub_intent.intent_id.clone(),  // Override specific fields
    escrow_id: hub_intent.intent_id.clone(),
    requester_addr: hub_intent.requester_addr.clone(),
    ..create_default_escrow_event_evm()  // Fill in the rest from default
};
```

**Benefits:**

- Reduces code duplication
- Makes tests more maintainable
- Allows focusing on fields that matter for each test
- Default helpers provide consistent defaults across tests

### 9. Format Requirements

Match the expected format for each constant type:

- **EVM addresses**: 20 bytes (40 hex chars + `0x` prefix = 42 chars)
- **MVM addresses**: 32 bytes (64 hex chars + `0x` prefix = 66 chars)
- **Transaction hashes**: 32 bytes (64 hex chars + `0x` prefix = 66 chars)
- **IDs**: Match the format used by the system (typically 32 bytes for MVM)
