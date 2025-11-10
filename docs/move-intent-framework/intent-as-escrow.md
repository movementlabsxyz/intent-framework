# Intent System as Escrow Mechanism

⚠️ **Important**: In this escrow system, the **verifier is an oracle** that approves or rejects escrow conditions. The verifier does NOT provide external data values - it only verifies whether predefined conditions are met and provides a signature to approve/reject the escrow release.

## Overview

The Aptos Intent Framework provides a simple escrow system through the `intent_as_escrow.move` module. This abstraction makes it easy to lock tokens and wait for verifier approval. The actual swap conditions and logic happen off-chain or on another chain - this chain just locks tokens and awaits binary yes/no from the verifier.

**Important**: Escrows created through `intent_as_escrow` **must** specify a reserved solver address. While the underlying `fa_intent_with_oracle` intent type supports optional reservations, escrows enforce this requirement for security (preventing signature replay attacks).

## Simple Escrow API

The `intent_as_escrow.move` module provides a clean interface for escrow functionality:

```move
// 1. Create escrow (must specify solver address)
let reservation = intent_reservation::new_reservation(solver_address);
let escrow_intent = intent_as_escrow::create_escrow(
    user,
    source_asset,
    verifier_public_key,
    expiry_time,
    intent_id, // Intent ID from hub chain (for cross-chain matching)
    reservation, // Required - escrow must specify a solver address
);

// 2. Solver takes escrow (solver signer must match reserved solver)
let (escrowed_asset, session) = intent_as_escrow::start_escrow_session(solver, escrow_intent);

// 3. Verifier approves/rejects
let (approval_value, verifier_signature) = intent_as_escrow::create_oracle_approval(
    &verifier_secret_key,
    true, // approve = true, reject = false
);

// 4. Complete escrow (solver signer must match reserved solver)
intent_as_escrow::complete_escrow(
    solver,
    session,
    solver_payment,
    approval_value,
    verifier_signature,
);
```

## API Functions

### Core Functions
- **`create_escrow()`** - Create escrow with verifier requirement (just locks tokens). **Requires** `reservation` parameter with solver address (unlike general `fa_intent_with_oracle` intents, escrows must always be reserved).
- **`start_escrow_session()`** - Start escrow for solver. Requires solver signer that matches the reserved solver address.
- **`complete_escrow()`** - Complete with verifier approval. Requires solver signer that matches the reserved solver address.
- **`revoke_escrow()`** - Revoke and return assets to user (not available - escrows are non-revocable)

### Helper Functions
- **`create_oracle_approval()`** - Generate verifier signature for approval/rejection
- **`get_oracle_approve()`** - Get approval constant (1)
- **`get_oracle_reject()`** - Get rejection constant (0)

## Escrow Lifecycle

### 1. Creation
User locks tokens and specifies:
- Which verifier can approve
- When escrow expires
- **Which solver address will receive funds** (required for escrows)
- (No swap parameters - actual logic is off-chain)

### 2. Solver Participation
Solver takes the escrowed assets (actual swap logic happens off-chain)
- The solver address must be specified at escrow creation
- Only the specified solver can start the session (enforced on-chain)

### 3. Verifier Verification
Verifier:
- Monitors conditions off-chain or on another chain
- Approves (1) or rejects (0) the escrow
- Provides Ed25519 signature

### 4. Completion
If verifier approves, tokens are released to solver

### 5. Fallback
If verifier rejects or escrow expires, user can reclaim tokens

## Architecture

The escrow system is deployed on a single Aptos chain. The verifier (oracle) monitors escrow conditions (possibly on other chains) and either approves or rejects the escrow release.

## Security Features

- **Timelock**: Escrow expires automatically
- **Verifier Verification**: Only authorized verifier can approve
- **Signature Verification**: Ed25519 signatures prevent forgery
- **Solver Reservation**: All escrows must specify a solver address at creation, preventing unauthorized claims and signature replay attacks
- **Event Transparency**: All actions are auditable

## Usage Examples

### Simple Token Escrow
```move
// User locks TokenA and waits for verifier approval
let reservation = intent_reservation::new_reservation(solver_address);
let escrow = intent_as_escrow::create_escrow(
    user,
    token_a_asset,
    verifier_public_key,
    expiry_time,
    intent_id, // Intent ID from hub chain
    reservation, // Required - must specify solver address
);
```

### Verifier Approval
```move
// Verifier monitors conditions and approves:
let (approval, signature) = intent_as_escrow::create_oracle_approval(
    &verifier_key,
    true, // approve
);

// Escrow releases tokens to solver
intent_as_escrow::complete_escrow(solver, session, payment, approval, signature);
```