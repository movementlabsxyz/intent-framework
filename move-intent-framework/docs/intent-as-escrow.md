# Intent System as Escrow Mechanism

## Overview

The Aptos Intent Framework implements a sophisticated escrow system through its intent mechanism. This document explains how the existing intent system functions as an escrow, particularly in the context of cross-chain architectures.

## Core Escrow Components

### 1. TradeIntent - The Escrow Contract

The `TradeIntent<Source, Args>` struct in `intent.move` is the core escrow mechanism:

```move
struct TradeIntent<Source, Args> has key {
    offered_resource: Source,        // ← Assets locked in escrow
    argument: Args,                  // ← Escrow conditions
    expiry_time: u64,               // ← Timelock expiry
    witness_type: TypeInfo,         // ← Verifier requirements
    reservation: Option<IntentReserved>, // ← Reserved solver
}
```

**Escrow Mapping:**
- `offered_resource` → Deposited tokens/assets
- `argument` → Escrow conditions (what must be fulfilled)
- `expiry_time` → Timelock (when escrow expires)
- `witness_type` → Verifier requirements (who can approve)
- `reservation` → Reserved solver (who gets the tokens)

### 2. Fungible Asset Escrow

The `fa_intent.move` module provides fungible asset-specific escrow functionality:

```move
struct FungibleAssetLimitOrder has store, drop {
    desired_metadata: Object<Metadata>,  // ← What token type to receive
    desired_amount: u64,                // ← How much to receive
    issuer: address,                    // ← Who can fulfill
}
```

## Escrow Lifecycle

### Phase 1: Deposit (Create Intent)
```move
// User deposits tokens and sets conditions
let intent_obj = fa_intent::create_fa_limit_order_intent(
    user,
    source_asset,           // ← Tokens to escrow
    desired_metadata,      // ← What they want in return
    desired_amount,        // ← How much they want
    expiry_time,           // ← When escrow expires
);
```

**What happens:**
1. User's tokens are locked in the intent
2. Escrow conditions are set (desired token type/amount)
3. Expiry time is established
4. Event is emitted for cross-chain communication

### Phase 2: Verification (Oracle Witness)
```move
// Oracle verifies conditions and provides witness
let witness = fa_intent::FungibleAssetRecipientWitness {};
intent::finish_intent_session(solver, intent_obj, witness);
```

**What happens:**
1. Oracle validates the escrow conditions
2. Oracle provides witness proving conditions are met
3. Tokens are released from escrow to solver
4. Escrow is completed and cleaned up

### Phase 3: Expiry (Fallback)
```move
// If oracle doesn't verify within expiry time
intent::revoke_intent(user, intent_obj);
```

**What happens:**
1. Escrow expires after `expiry_time`
2. Tokens are returned to original depositor
3. Escrow is cleaned up

## Cross-Chain Escrow Architecture

### Hub Chain (Escrow Chain)
- **Role**: Hosts the escrow contracts
- **Components**: `intent.move`, `fa_intent.move`
- **Function**: Locks tokens until oracle verification

### Connected Chain (Oracle Chain)
- **Role**: Provides oracle verification
- **Components**: Oracle services, event listeners
- **Function**: Monitors escrow events and provides witness

### Cross-Chain Communication
```move
#[event]
struct LimitOrderEvent has store, drop {
    source_metadata: Object<Metadata>,
    source_amount: u64,
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    issuer: address,
    expiry_time: u64,
}
```

**Flow:**
1. Hub Chain emits `LimitOrderEvent` when escrow is created
2. Connected Chain oracle listens to events
3. Oracle verifies conditions on connected chain
4. Oracle provides witness back to hub chain
5. Escrow releases tokens to solver

## Oracle Integration

### Witness System
The intent system uses a witness-based verification:

```move
struct FungibleAssetRecipientWitness has drop {}
```

**Oracle Requirements:**
1. Must be able to create the specific witness type
2. Must verify escrow conditions are met
3. Must provide witness within expiry time

### Signature Verification
For additional security, the system supports signature verification:

```move
struct IntentReserved has store {
    solver: address,
    signature: vector<u8>,
}
```

## Escrow States

| State | Description | Actions Available |
|-------|-------------|-------------------|
| **Active** | Tokens locked, waiting for oracle | Oracle can verify, User can revoke |
| **Verified** | Oracle provided witness | Solver can claim tokens |
| **Expired** | Past expiry time | User can reclaim tokens |
| **Completed** | Tokens released to solver | None (escrow deleted) |

## Security Features

### 1. Timelock Protection
- Escrow automatically expires after `expiry_time`
- Prevents indefinite token locking
- Allows depositor to reclaim tokens

### 2. Witness Verification
- Only valid witnesses can complete escrow
- Oracle must prove conditions are met
- Prevents unauthorized token release

### 3. Signature Verification
- Solvers can reserve escrow with signatures
- Prevents front-running
- Ensures only authorized solvers can claim

### 4. Event Transparency
- All escrow actions emit events
- Cross-chain visibility
- Audit trail for all operations

## Usage Examples

### Simple Token Swap Escrow
```move
// 1. User wants to swap 100 TokenA for 200 TokenB
let intent = fa_intent::create_fa_limit_order_intent(
    user,
    token_a_asset,      // 100 TokenA locked
    token_b_metadata,  // Want TokenB
    200,               // Want 200 TokenB
    expiry_time,
);

// 2. Oracle verifies TokenB is available
let witness = fa_intent::FungibleAssetRecipientWitness {};
intent::finish_intent_session(solver, intent, witness);

// 3. User gets 200 TokenB, Solver gets 100 TokenA
```

### Cross-Chain Price Oracle Escrow
```move
// 1. User locks USDC, wants ETH at specific price
let intent = fa_intent::create_fa_limit_order_intent(
    user,
    usdc_asset,        // 1000 USDC locked
    eth_metadata,      // Want ETH
    eth_amount,        // Amount based on oracle price
    expiry_time,
);

// 2. Cross-chain oracle monitors price
// 3. When price target is hit, oracle provides witness
// 4. Escrow releases ETH to user
```

## Benefits of Intent-Based Escrow

1. **Generic**: Works with any asset type, not just tokens
2. **Flexible**: Conditions can be complex (price, time, etc.)
3. **Secure**: Multiple verification layers (witness, signature, expiry)
4. **Transparent**: All actions emit events for monitoring
5. **Cross-Chain**: Built-in event system for multi-chain coordination
6. **Extensible**: Easy to add new condition types and witnesses

## Conclusion

The Aptos Intent Framework provides a robust, secure, and flexible escrow system through its intent mechanism. By leveraging the existing `TradeIntent` and `FungibleAssetLimitOrder` structures, developers can implement sophisticated escrow logic without building custom contracts.

The system is particularly well-suited for cross-chain architectures where:
- Hub chains host the escrow contracts
- Connected chains provide oracle verification
- Events enable seamless cross-chain communication
- Witness systems ensure secure condition verification

This approach eliminates the need for custom escrow contracts while providing more functionality and security than traditional escrow implementations.
