# Outflow Implementation Plan

## Overview

This document outlines the strategy for implementing the **outflow** functionality, which is the reverse direction of the current cross-chain intent flow.

--------------------------------------------------------------------------------

## Current Flow (Inflow) - For Reference

**Current implementation:**

1. **Hub Chain**: Requester creates cross-chain request intent (tokens locked on connected chain, desired on hub)
2. **Connected Chain**: Requester creates escrow with tokens locked
3. **Hub Chain**: Solver fulfills intent by providing desired tokens to requester on hub
4. **Verifier**: Validates fulfillment and generates approval signature
5. **Connected Chain**: Escrow released to reserved solver using verifier signature

--------------------------------------------------------------------------------

## Target Flow (Outflow)

**What we need to implement:**

1. **Hub Chain**: Requester creates request intent with tokens **locked on hub** (requester tokens going IN to hub)
2. **Connected Chain**: Solver creates **connected_chain_fulfill** transaction that **immediately** transfers desired tokens directly to requester address (connected chain) (single transaction, includes `intent_id` as metadata, no escrow, no verifier involvement)
3. **Verifier**: Receives transaction hash from solver, queries transaction by hash, extracts `intent_id` and validates transaction matches intent requirements, then generates approval signature
4. **Hub Chain**: Solver fulfills hub intent using oracle-guarded intent mechanism with verifier signature (unlocks tokens to reserved solver)

--------------------------------------------------------------------------------

## Key Requirements

### Critical Requirement: Immediate Solver Transfer

**MANDATORY**: The solver must **immediately** transfer tokens to the requester on the connected chain. This transfer:

- Must happen in a single transaction
- Must NOT require verifier approval or signature
- Must NOT use escrow or locking mechanisms
- Must be a direct transfer from solver to requester
- Must include `intent_id` in the transaction for verifier tracking
- **MUST NOT require any action from the requester** - the requester receives tokens passively without needing to call any functions or submit any transactions

The verifier's role is **only** to:

1. Observe that the transfer occurred
2. Validate the transfer matches the intent requirements
3. Generate approval signature (signs `intent_id`)

**Hub Fulfillment**: Solver fulfills the hub intent using the existing oracle-guarded intent mechanism. The verifier signature is required for fulfillment, and funds go to the reserved solver address.

### Hub Chain Request Intent

- Requester locks tokens on hub chain (opposite of current flow)
- Intent specifies:
  - `offered_amount`: Amount locked on hub chain
  - `offered_chain_id`: Hub chain ID (where tokens are locked)
  - `desired_amount`: Amount desired on connected chain
  - `desired_chain_id`: Connected chain ID (where solver will provide tokens)
  - `intent_id`: For cross-chain linking
  - `requester_address_connected_chain`: Address on connected chain where solver should send tokens
  - `solver`: Reserved solver address (who will receive tokens on hub when released)

### Connected Chain Transaction

- Solver **immediately** transfers tokens to requester on connected chain
- Transfer must be direct (no escrow, no verifier involvement)
- **Requester takes NO action** - tokens are transferred directly to their address
- Transaction includes:
  - `intent_id`: Links to hub request intent (for verifier tracking)
  - `desired_amount`: Amount transferred to requester
  - `requester_address_connected_chain`: Recipient address (must match intent)
  - `solver_address`: Solver's address (for verification)

### Verifier Validation

- Verifier observes:
  1. Hub request intent with tokens locked
  2. Connected chain transfer event showing tokens were sent to requester
- Verifier validates:
  - Transfer event on connected chain matches intent requirements
  - Requester address matches intent
  - Amount matches desired amount
  - Solver address matches reserved solver
  - Transfer was completed (requester received tokens)
- Verifier generates approval signature after validation
- Solver fulfills hub intent using oracle-guarded intent mechanism with verifier signature

--------------------------------------------------------------------------------

## Strategy Analysis

### Scenario A: Move VM Connected Chain

#### Current Move Intent Framework Capabilities

- `fa_intent_cross_chain::create_cross_chain_request_intent_entry()`: Creates request intent on hub
- `fa_intent_cross_chain::fulfill_cross_chain_request_intent()`: Solver fulfills on hub
- `intent_as_escrow::create_escrow_from_fa()`: Creates escrow on connected chain
- `intent_as_escrow::complete_escrow_from_fa()`: Completes escrow with verifier signature

#### Implementation Approach for Outflow (Move VM)

##### Connected Chain Fulfill Transaction with Intent ID Metadata (Move VM)

- On **connected chain**: Solver creates a **connected_chain_fulfill** transaction that:
  - **Immediately** transfers tokens directly to requester address (connected chain) using standard Move transfer functions (e.g., `primary_fungible_store::deposit()`)
  - Includes `intent_id` as metadata in the transaction payload
  - Tokens are transferred in a single atomic transaction (no escrow, no waiting)
- Transaction format:
  - Standard Move transfer function call
  - `intent_id` encoded in transaction metadata/script arguments
  - Verifier can extract `intent_id` from transaction payload when querying by transaction hash
- Solver provides transaction hash to verifier (via API or off-chain communication)
- Verifier validates:
  - Queries transaction by hash using Move VM RPC
  - Extracts `intent_id` from transaction metadata
  - Validates transaction parameters match intent requirements:
    - `to` address matches requester address (connected chain)
    - `amount` matches desired amount
    - `from` address (solver) matches reserved solver
  - Validates transfer was completed successfully
- On **hub chain**: Verifier generates approval signature after validation
- Anyone with signature can fulfill the hub intent (tokens go to reserved solver)

##### Advantages (Move VM)

- **No contract changes needed for transfer** - uses standard Move transfer functions
- **Single transaction** - solver transfers tokens immediately
- **On-chain metadata** - `intent_id` is part of transaction payload, verifiable on-chain
- **Standard format** - transaction layout format can be documented and standardized
- **Verifier validation** - verifier can query transaction and extract all needed information
- **Pre-flight validation function** - contract can provide view function to validate transaction format (not values - contract doesn't know correct values, only verifier does)

--------------------------------------------------------------------------------

### Scenario B: EVM Connected Chain

#### Current EVM Intent Framework Capabilities

- `IntentEscrow::createEscrow()`: Creates escrow on EVM chain
- `IntentEscrow::claim()`: Claims escrow with verifier signature
- `IntentEscrow::deposit()`: Deposits additional funds to escrow

#### Implementation Approach for Outflow (EVM)

##### Connected Chain Fulfill Transaction with Intent ID Metadata (EVM)

- On **EVM chain**: Solver creates a **connected_chain_fulfill** transaction that:
  - **Immediately** transfers ERC20 tokens directly to requester address (connected chain) using standard `transfer(to, amount)` function
  - Includes `intent_id` as metadata in the transaction `data` field
  - Tokens are transferred in a single atomic transaction (no escrow, no waiting)
- Transaction format:

  ```text
  Transaction data = 
    Function selector (4 bytes): 0xa9059cbb (transfer(address,uint256))
    + to address (32 bytes, right-padded)
    + amount (32 bytes)
    + intent_id (32 bytes)  ← Metadata appended after function parameters
  ```

  - The ERC20 contract's `transfer()` function reads only `to` and `amount`, ignoring the extra `intent_id` bytes
  - The `intent_id` remains in the transaction data and is verifiable on-chain
- Solver provides transaction hash to verifier (via API or off-chain communication)
- Verifier validates:
  - Queries transaction by hash using `eth_getTransactionByHash`
  - Decodes transaction `data` field to extract:
    - Function call parameters: `to` address, `amount`
    - Metadata: `intent_id` (bytes after function parameters)
  - Validates all parameters match intent requirements:
    - `to` address matches requester address (connected chain)
    - `amount` matches desired amount
    - `from` address (solver) matches reserved solver
    - `intent_id` matches hub request intent
  - Validates transaction was confirmed and transfer completed
- On **hub chain**: Verifier generates approval signature after validation
- Anyone with signature can fulfill the hub intent (tokens go to reserved solver)

##### Advantages (EVM)

- **No contract changes needed for transfer** - uses standard ERC20 `transfer()` function
- **Single transaction** - solver transfers tokens immediately (no approval needed if solver owns tokens)
- **On-chain metadata** - `intent_id` is part of transaction data, verifiable on-chain
- **Standard format** - transaction layout format can be documented and standardized
- **Verifier validation** - verifier can query transaction and extract all needed information
- **Pre-flight validation function** - contract can provide view function to validate transaction format (not values - contract doesn't know correct values, only verifier does)

--------------------------------------------------------------------------------

## Implementation Strategy

### Task 1: Analysis and Design

1. **Generalize hub request intent creation**:
   - Current: `create_cross_chain_request_intent_entry()` creates `FungibleAssetLimitOrder` (inflow - no signature needed)
   - Needed: Support both inflow and outflow request intents
   - **Inflow request intent** (current):
     - Uses `fa_intent::create_fa_to_fa_intent()` → creates `FungibleAssetLimitOrder`
     - Withdraws 0 tokens (tokens locked on connected chain)
     - Fulfillment: `fulfill_cross_chain_request_intent()` → no signature required
   - **Outflow request intent** (new):
     - Uses `fa_intent_with_oracle::create_fa_to_fa_intent_with_oracle_requirement()` → creates `OracleGuardedLimitOrder`
     - Withdraws actual tokens (tokens locked on hub)
     - Fulfillment: requires verifier signature via `fa_intent_with_oracle::finish_fa_receiving_session_with_oracle()`
   - **Approach**: Create wrapper functions:
     - `create_inflow_request_intent()` - wrapper around current `create_cross_chain_request_intent_entry()`
     - `create_outflow_request_intent()` - new function that creates oracle-guarded intent
     - Both call a generalized base function or share common logic

2. **Determine requester address (connected chain) storage**:
   - Where should `requester_address_connected_chain` be stored in hub request intent?
   - For outflow: Store in `OracleGuardedLimitOrder` struct (extend it)
   - For inflow: Not needed (tokens go to solver on the connected chain, not requester)
   - Or use separate mapping `intent_id -> requester_address_connected_chain`

3. **Define connected_chain_fulfill transaction format**:
   - **For Move VM**: Standard transfer function with `intent_id` in transaction metadata/script arguments
   - **For EVM**: Standard ERC20 `transfer()` with `intent_id` appended in transaction `data` field (32 bytes after function parameters)
   - Document exact transaction format specification for both chains
   - Ensure `intent_id` linking is clear and verifiable

4. **Design verifier validation logic**:
   - Verifier receives transaction hash from solver (via API or off-chain)
   - Query transaction by hash on connected chain
   - Extract `intent_id` and transaction parameters from transaction data
   - Match hub intent with connected chain transaction by `intent_id`
   - Validate all parameters match intent requirements (requester address (connected chain), amount, solver address)
   - Verify transaction was confirmed and transfer completed successfully

### Task 2: Move Implementation (Move VM Connected Chain)

1. **Create inflow request intent wrapper function**:
   - New function: `create_inflow_request_intent()` in `fa_intent_cross_chain.move`
   - Wrapper around current `create_cross_chain_request_intent_entry()` for clarity and consistency
   - Creates `FungibleAssetLimitOrder` intent using `fa_intent::create_fa_to_fa_intent()`
   - Withdraws 0 tokens (tokens locked on connected chain, not hub)
   - No signature required for fulfillment
   - Parameters: Same as current `create_cross_chain_request_intent_entry()`
   - Returns `Object<TradeIntent<FungibleStoreManager, FungibleAssetLimitOrder>>`

2. **Create outflow request intent wrapper function**:
   - New function: `create_outflow_request_intent()` in `fa_intent_cross_chain.move`
   - Creates oracle-guarded intent using `fa_intent_with_oracle::create_fa_to_fa_intent_with_oracle_requirement()`
   - Parameters:
     - All standard cross-chain intent parameters
     - `requester_address_connected_chain`: Address on connected chain where solver sends tokens
     - `verifier_public_key`: Verifier's public key for `OracleSignatureRequirement`
   - Withdraws actual tokens from requester (tokens locked on hub, not 0)
   - Creates `OracleGuardedLimitOrder` with `requester_address_connected_chain` field (needs struct extension)
   - Sets `revocable = false` (critical for cross-chain safety)
   - Returns `Object<TradeIntent<FungibleStoreManager, OracleGuardedLimitOrder>>`

3. **Extend `OracleGuardedLimitOrder` struct**:
   - Add `requester_address_connected_chain: Option<address>` field to `OracleGuardedLimitOrder` struct
   - Located in `fa_intent_with_oracle.move`
   - **Decision**: Store in `OracleGuardedLimitOrder` struct (not separate mapping)
   - This field is required for outflow intents (must be `some`), optional for regular oracle intents (can be `none`)

4. **Define connected_chain_fulfill transaction format**:
   - Document standard transaction format for Move VM
   - Standard transfer function call (e.g., `primary_fungible_store::deposit()`)
   - `intent_id` encoded in transaction metadata/script arguments
   - Transaction format specification for solver to follow

5. **Add validation function** (optional but recommended):
   - View function: `validate_connected_chain_fulfill()`
   - Validates transaction format only (not values - contract doesn't know correct values):
     - Transaction includes `intent_id` in metadata
     - Transaction format matches expected structure
     - All required fields are present
   - Note: Actual value validation (matching intent requirements) is done by verifier, not contract
   - Returns format validation result (can be called off-chain by solver before submitting transaction)

6. **Hub fulfillment mechanism**:
   - Use existing oracle-guarded intent mechanism (`fa_intent_with_oracle`)
   - Hub request intent is created as oracle-guarded intent (requires verifier signature for fulfillment)
   - Solver fulfills intent on hub using `finish_fa_receiving_session_with_oracle()` with verifier signature
   - Verifier signature is provided as `OracleSignatureWitness` (signature signs `intent_id`)
   - No new function needed - existing oracle-guarded intent flow handles this

### Task 3: EVM Implementation

1. **Extend hub request intent** (same as Task 2)

2. **Define connected_chain_fulfill transaction format**:
   - Document standard transaction format for EVM
   - Standard ERC20 `transfer(to, amount)` function call
   - `intent_id` appended as metadata in transaction `data` field (32 bytes after function parameters)
   - Transaction format specification:

     ```text
     data = 0xa9059cbb (transfer selector)
          + to (32 bytes, right-padded)
          + amount (32 bytes)
          + intent_id (32 bytes)  ← Metadata
     ```

   - No contract changes needed for transfer - uses existing ERC20 standard

3. **Add validation function** (optional but recommended):
   - View function in `IntentEscrow` contract: `validateConnectedChainFulfill()`
   - Validates transaction format only (not values - contract doesn't know correct values):
     - Transaction `data` field includes `intent_id` metadata (32 bytes after function parameters)
     - Transaction format matches expected structure:

       ```text
       data = function_selector (4 bytes)
            + to (32 bytes)
            + amount (32 bytes)
            + intent_id (32 bytes)  ← Must be present
       ```

     - All required fields are present and properly formatted
   - Note: Actual value validation (matching intent requirements) is done by verifier, not contract
   - Returns format validation result (can be called off-chain by solver before submitting transaction)

4. **Hub fulfillment mechanism**: Already implemented in Task 2 (no additional work needed for EVM)

### Task 4: Verifier Integration

1. **Event monitoring**:
   - Monitor hub `LimitOrderEvent` for outflow intents
   - Receive `connected_chain_fulfill` transaction hash from solver (via API or off-chain)
   - Match by `intent_id` extracted from transaction

2. **Transaction validation logic**:
   - **For EVM**: Query transaction by hash using `eth_getTransactionByHash`
     - Decode transaction `data` field
     - Extract function parameters: `to` address, `amount`
     - Extract metadata: `intent_id` (bytes after function parameters)
   - **For Move VM**: Query transaction by hash using Move VM RPC
     - Extract `intent_id` from transaction metadata/script arguments
     - Extract transfer parameters from transaction payload
   - Validate all parameters match intent requirements:
     - `intent_id` matches hub request intent
     - `to`/requester address (connected chain) matches intent's requester address (connected chain)
     - `amount` matches intent's desired amount
     - `from`/solver address matches reserved solver
   - Verify transaction was confirmed and transfer completed successfully

3. **Approval generation**:
   - After successful validation, sign `intent_id` to generate approval signature
   - Solver uses signature to fulfill hub intent via oracle-guarded intent mechanism
   - Funds always go to reserved solver, regardless of who calls the fulfillment function

--------------------------------------------------------------------------------

## Code Changes Required

### Generalization of Hub Request Intent

**Current State:**

- `create_cross_chain_request_intent_entry()` in `fa_intent_cross_chain.move` creates `FungibleAssetLimitOrder` intents
- Uses `fa_intent::create_fa_to_fa_intent()` - no signature required for fulfillment
- Withdraws 0 tokens (tokens locked on connected chain)
- Fulfillment: `fulfill_cross_chain_request_intent()` → `fa_intent::finish_fa_receiving_session_with_event()` (no signature)

**Changes Needed:**

1. **Create inflow request intent wrapper function**:
   - New function: `create_inflow_request_intent()` in `fa_intent_cross_chain.move`
   - Wrapper around current `create_cross_chain_request_intent_entry()` for clarity and consistency

2. **Create outflow request intent wrapper function**:
   - `create_outflow_request_intent()` in `fa_intent_cross_chain.move`
   - Uses `fa_intent_with_oracle::create_fa_to_fa_intent_with_oracle_requirement()`
   - Withdraws actual tokens from requester (tokens locked on hub)
   - Creates `OracleGuardedLimitOrder` (requires verifier signature for fulfillment)
   - Adds `requester_address_connected_chain` parameter

3. **Extend `OracleGuardedLimitOrder` struct** in `fa_intent_with_oracle.move`:
   - Add `requester_address_connected_chain: Option<address>` field
   - Used only for outflow intents (None for regular oracle intents)

4. **Fulfillment functions**:
   - Inflow: Keep existing `fulfill_cross_chain_request_intent()` (no changes)
   - Outflow: Use existing `fa_intent_with_oracle::finish_fa_receiving_session_with_oracle()` with verifier signature

**Key Differences:**

| Aspect | Inflow (Current) | Outflow (New) |
|--------|------------------|---------------|
| Intent Type | `FungibleAssetLimitOrder` | `OracleGuardedLimitOrder` |
| Creation Function | `fa_intent::create_fa_to_fa_intent()` | `fa_intent_with_oracle::create_fa_to_fa_intent_with_oracle_requirement()` |
| Tokens Locked | 0 (on hub), actual (on connected) | Actual (on hub), 0 (on connected) |
| Fulfillment | No signature required | Verifier signature required |
| Requester Address | Not needed | `requester_address_connected_chain` required |

--------------------------------------------------------------------------------

## Security Considerations

1. **Requester Address Validation**:

   - Ensure requester address (connected chain) is valid and not address(0)
   - Verify requester address (connected chain) matches intent requirements

2. **Amount Validation**:

   - Verify connected chain amount matches hub desired amount
   - Handle potential rounding/decimals differences

3. **Solver Authorization**:

   - Ensure only reserved solver can fulfill the hub intent
   - Verify solver address matches intent reservation

4. **Verifier Signature Security**:

   - Ensure signature is for correct `intent_id`
   - Prevent signature replay attacks
