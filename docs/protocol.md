# Protocol Specification

This document specifies the cross-chain intent protocol: how intents, escrows, and verifiers work together across chains. For component-specific implementation details, see the [component documentation](#component-documentation).

## Table of Contents

- [Protocol Overview](#protocol-overview)
- [Cross-Chain Flow](#cross-chain-flow)
- [Cross-Chain Linking Mechanism](#cross-chain-linking-mechanism)
- [Verifier Validation Protocol](#verifier-validation-protocol)
- [Security Requirements](#security-requirements)

## Protocol Overview

The cross-chain intent protocol enables secure asset transfers between chains using a verifier-based approval mechanism:

1. **Hub Chain**: Intents are created and fulfilled (see [Move Intent Framework](move-intent-framework/README.md))
2. **Connected Chain**: Escrows lock funds awaiting verifier approval (see [EVM Intent Framework](evm-intent-framework/README.md) or Move escrows)
3. **Verifier Service**: Monitors both chains and provides approval signatures (see [Trusted Verifier](trusted-verifier/README.md))

The protocol links these components using `intent_id` to correlate events across chains.

## Cross-Chain Flow

The intent framework enables cross-chain escrow operations where intents are created on a hub chain and escrows are created on connected chains. The verifier monitors both chains and provides approval signatures to authorize escrow release.

### Standard Flow

```mermaid
sequenceDiagram
    participant User
    participant Hub as Hub Chain<br/>(Move)
    participant Verifier as Trusted Verifier<br/>(Rust)
    participant Connected as Connected Chain<br/>(Move/EVM)
    participant Solver

    Note over User,Solver: Phase 1: Intent Creation on Hub Chain
    User->>User: create_cross_chain_draft_intent()<br/>(off-chain, creates IntentDraft)
    User->>Solver: Send draft
    Solver->>Solver: Solver signs<br/>(off-chain, returns Ed25519 signature)
    Solver->>User: Returns signature
    User->>Hub: create_cross_chain_request_intent_entry(<br/>offered_metadata, offered_amount, offered_chain_id,<br/>desired_metadata, desired_amount, desired_chain_id,<br/>expiry_time, intent_id, solver, solver_signature)
    Hub->>Verifier: LimitOrderEvent(intent_id, offered_amount,<br/>offered_chain_id, desired_amount,<br/>desired_chain_id, expiry, revocable=false)

    Note over User,Solver: Phase 2: Escrow Creation on Connected Chain
    alt Move Chain
        User->>Connected: create_escrow_from_fa(<br/>source_metadata, amount, verifier_pk,<br/>expiry_time, intent_id, reserved_solver)
    else EVM Chain
        User->>Connected: createEscrow(intentId, token,<br/>amount, reservedSolver)
    end
    Connected->>Connected: Lock assets
    Connected->>Verifier: OracleLimitOrderEvent/EscrowInitialized(<br/>intent_id, reserved_solver, revocable=false)

    Note over User,Solver: Phase 3: Intent Fulfillment on Hub Chain
    Solver->>Hub: fulfill_cross_chain_request_intent(<br/>intent, payment_amount)
    Hub->>Verifier: LimitOrderFulfillmentEvent(<br/>intent_id, solver, provided_amount)

    Note over User,Solver: Phase 4: Verifier Validation and Approval
    Verifier->>Verifier: Match intent_id between<br/>fulfillment and escrow
    Verifier->>Verifier: Validate fulfillment<br/>conditions met
    Verifier->>Verifier: Generate approval signature

    Note over User,Solver: Phase 5: Escrow Release on Connected Chain
    Verifier->>Solver: Delivers approval signature<br/>(Ed25519 for Move, ECDSA for EVM)<br/>Signature itself is the approval
    alt Move Chain
        Note over Solver: Anyone can call<br/>(funds go to reserved_solver)
        Solver->>Connected: complete_escrow_from_fa(<br/>escrow_intent, payment_amount,<br/>verifier_signature_bytes)
    else EVM Chain
        Note over Solver: Anyone can call<br/>(funds go to reservedSolver)
        Solver->>Connected: claim(intentId, signature)
    end
    Connected->>Connected: Verify signature
    Connected->>Connected: Transfer to reserved_solver
```

### Flow Steps

1. **Off-chain (before Hub)**: User and solver negotiate using the reserved intent flow:
   - **Step 1**: User creates draft using `create_cross_chain_draft_intent()` with `offered_amount` (amount that will be locked in escrow on connected chain), `offered_chain_id`, and `desired_chain_id`
   - **Step 2**: Solver adds their address using `add_solver_to_draft_intent()`, signs the `IntentToSign` using `hash_intent()`, and returns the Ed25519 signature
2. **Hub**: User calls `create_cross_chain_request_intent_entry()` with `offered_amount` (amount that will be locked in escrow on connected chain), `intent_id`, `offered_chain_id`, `desired_chain_id`, `solver` address, and `solver_signature`. The function looks up the solver's public key from the on-chain solver registry, verifies the signature, and creates a reserved intent (emits `LimitOrderEvent` with `offered_amount`, `offered_chain_id`, `desired_chain_id`, `revocable=false`). The intent is **reserved** for the specified solver, ensuring solver commitment across chains.

   **Note**: The solver must be registered in the solver registry before calling this function. The public key is stored on-chain in the registry, eliminating the need to pass it explicitly.
3. **Connected Chain**: User creates escrow using `create_escrow_from_fa()` (Move) or `createEscrow()` (EVM) with `intent_id`, verifier public key, and **reserved solver address** (emits `OracleLimitOrderEvent`/`EscrowInitialized`, `revocable=false`).
4. **Solver**: Observes the request intent on Hub chain (from step 2) and the escrow on Connected Chain (from step 3).
5. **Hub**: Solver fulfills the intent using `fulfill_cross_chain_request_intent()` (emits `LimitOrderFulfillmentEvent`)
6. **Verifier**: observes fulfillment + escrow, signs the `intent_id` to generate approval signature (signature itself is the approval)
7. **Anyone**: submits `complete_escrow_from_fa()` (Move) or `claim()` (EVM) on connected chain with verifier signature (Ed25519 for Move, ECDSA for EVM). The transaction can be sent by anyone, but funds always transfer to the reserved solver address specified at escrow creation.

**Note**: All escrows must specify a reserved solver address at creation. Funds are always transferred to the reserved solver when the escrow is claimed, regardless of who sends the transaction.

## Cross-Chain Linking Mechanism

The protocol uses `intent_id` to link intents across chains:

### Intent ID Assignment

1. **Hub Chain Regular Intent**:
   - `intent_id` = `intent_address` (object address)
   - Stored in `LimitOrderEvent.intent_id`

2. **Hub Chain Cross-Chain Request Intent**:
   - `intent_id` explicitly provided as parameter
   - Used when tokens are locked on a different chain
   - Stored in `FungibleAssetLimitOrder.intent_id` as `Option<address>`

3. **Connected Chain Escrow**:
   - `intent_id` provided at creation, linking to hub intent
   - Must match hub chain intent's `intent_id` for verifier matching

### Event Correlation

The verifier matches events across chains:

```text
Hub Chain: LimitOrderEvent.intent_id
    ↓
    (matches)
    ↓
Connected Chain: OracleLimitOrderEvent.intent_id / EscrowInitialized.intentId
```

**Matching Process**:

1. Verifier observes `LimitOrderEvent` → stores `RequestIntentEvent` with `intent_id`
2. Verifier observes escrow event → stores `EscrowEvent` with `intent_id`
3. When `LimitOrderFulfillmentEvent` observed → matches `fulfillment.intent_id` with `escrow.intent_id`
4. If match found and validation passes → generates approval signature

## Verifier Validation Protocol

The verifier performs cross-chain validation before generating approvals:

### Validation Steps

1. **Intent Safety Check**: Validates `escrow.revocable == false` (CRITICAL - see [Security Requirements](#security-requirements))
2. **Event Matching**: Links escrow events to intent events via `intent_id`
3. **Fulfillment Verification**: Confirms hub intent fulfillment occurred
4. **Condition Validation**: Verifies fulfillment meets escrow requirements
5. **Approval Generation**: Creates cryptographic signature (Ed25519 for Move, ECDSA for EVM)

### Validation Workflow

```mermaid
sequenceDiagram
    participant Monitor as Event Monitor
    participant Validator as Cross-Chain Validator
    participant Crypto as Crypto Service

    Note over Monitor,Crypto: Continuous Event Polling
    loop Every polling interval
        Monitor->>Hub Chain: Poll for LimitOrderEvent, LimitOrderFulfillmentEvent
        Monitor->>Connected Chain: Poll for escrow events
        Monitor->>Monitor: Store events in cache
    end

    Note over Monitor,Crypto: Validation and Approval
    Monitor->>Validator: Match events by intent_id
    Validator->>Validator: Validate escrow.revocable == false
    Validator->>Validator: Validate fulfillment conditions
    alt Validation passed
        Monitor->>Crypto: Generate signature
        Crypto->>Monitor: Return approval signature
    else Validation failed
        Monitor->>Monitor: Log rejection
    end
```

For detailed validation logic, see [Trusted Verifier](trusted-verifier/README.md).

## Security Requirements

### Non-Revocable Escrow Validation

⚠️ **CRITICAL**: All escrow intents MUST be created with `revocable = false`.

**Why**: Escrow funds must remain locked until verifier approval or expiry. If escrows were revocable, users could withdraw funds after verifiers trigger actions elsewhere, breaking the protocol's security guarantees.

**Enforcement**:

- Move escrow creation enforces non-revocable: `intent_as_escrow.move:109`
- Verifier validates before approval: `trusted-verifier/src/validator/mod.rs:99-105`
- EVM escrows use contract-defined expiry instead of revocation

### Reserved Solver Address

All escrows MUST specify a reserved solver address at creation:

- **Move Escrows**: `reservation: IntentReserved` required
- **EVM Escrows**: `reservedSolver` parameter required (never `address(0)`)
- Funds ALWAYS transfer to reserved solver, regardless of transaction sender
- Prevents signature replay attacks

**Security Benefit**: Even if approval signature is leaked, funds can only go to the authorized solver address.

### Cryptographic Operations

**Aptos/Move Chains**:

- Ed25519 signatures for verifier approvals
- Signature over BCS-encoded `intent_id` (address) - the signature itself is the approval
- Public key embedded in escrow creation

**EVM Chains**:

- ECDSA signatures for verifier approvals
- Message: `keccak256(intentId)` - signature itself is the approval
- Ethereum signed message format
