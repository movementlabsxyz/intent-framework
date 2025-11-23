# Intent System as Escrow Mechanism

⚠️ **Important**: In this escrow system, the **verifier is an oracle** that approves escrow conditions. The verifier signs the `intent_id` - the signature itself is the approval. If the verifier doesn't sign, there's no approval.

## Overview

The Move VM Intent Framework provides a simple escrow system through the `intent_as_escrow.move` module. This abstraction makes it easy to lock tokens and wait for verifier approval. The actual swap conditions and logic happen off-chain or on another chain - this chain just locks tokens and awaits binary yes/no from the verifier.

**Important**: Escrows created through `intent_as_escrow` **must** specify a reserved solver address. While the underlying `fa_intent_with_oracle` intent type supports optional reservations, escrows enforce this requirement for security (preventing signature replay attacks).

## Simple Escrow API

The `intent_as_escrow.move` module provides a clean interface for escrow functionality:

```move
// 1. Create escrow (must specify solver address)
let reservation = intent_reservation::new_reservation(solver_address);
let escrow_intent = intent_as_escrow::create_escrow(
    requester_signer,
    offered_asset,
    verifier_public_key,
    expiry_time,
    intent_id, // Intent ID from hub chain (for cross-chain matching)
    reservation, // Required - escrow must specify a solver address
);

// 2. Solver takes escrow (solver signer must match reserved solver)
let (escrowed_asset, session) = intent_as_escrow::start_escrow_session(solver, escrow_intent);

// 3. Verifier signs the intent_id - signature itself is the approval
let intent_id = @0x1; // Same intent_id used when creating escrow
let verifier_signature = ed25519::sign_arbitrary_bytes(&verifier_secret_key, bcs::to_bytes(&intent_id));

// 4. Complete escrow (solver signer must match reserved solver)
intent_as_escrow::complete_escrow(
    solver,
    session,
    solver_payment,
    verifier_signature,
);
```

## API Functions

### Core Functions

- **`create_escrow()`** - Create escrow with verifier requirement (just locks tokens). **Requires** `reservation` parameter with solver address (unlike general `fa_intent_with_oracle` intents, escrows must always be reserved).
- **`start_escrow_session()`** - Start escrow for solver. Requires solver signer that matches the reserved solver address.
- **`complete_escrow()`** - Complete with verifier signature. Requires solver signer that matches the reserved solver address. The signature itself is the approval - verifier signs the `intent_id`.
- **`revoke_escrow()`** - Revoke and return assets to requester (not available - escrows are non-revocable)

## Escrow Lifecycle

### 1. Creation

Requester locks tokens and specifies:

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
- Signs the `intent_id` to approve the escrow
- Provides Ed25519 signature (signature itself is the approval)

### 4. Completion

If verifier signature verifies correctly, tokens are released to solver

### 5. Fallback

If escrow expires, requester can reclaim tokens

## Architecture

The escrow system is deployed on a single Move VM chain. The verifier (oracle) monitors escrow conditions (possibly on other chains) and signs the `intent_id` to approve the escrow release. The signature itself is the approval.

## Security Features

- **Timelock**: Escrow expires automatically
- **Verifier Verification**: Only authorized verifier can approve
- **Signature Verification**: Ed25519 signatures prevent forgery
- **Solver Reservation**: All escrows must specify a solver address at creation, preventing unauthorized claims and signature replay attacks
- **Event Transparency**: All actions are auditable

## Usage Examples

### Simple Token Escrow

```move
// Requester locks TokenA and waits for verifier approval
let reservation = intent_reservation::new_reservation(solver_address);
let escrow = intent_as_escrow::create_escrow(
    requester_signer,
    token_a_asset,
    verifier_public_key,
    expiry_time,
    intent_id, // Intent ID from hub chain
    reservation, // Required - must specify solver address
);
```

### Verifier Approval

```move
// Verifier monitors conditions and signs the intent_id:
let intent_id = @0x1; // Same intent_id used when creating escrow
let verifier_signature = ed25519::sign_arbitrary_bytes(&verifier_key, bcs::to_bytes(&intent_id));

// Escrow releases tokens to solver (signature itself is the approval)
intent_as_escrow::complete_escrow(solver, session, payment, verifier_signature);
```
