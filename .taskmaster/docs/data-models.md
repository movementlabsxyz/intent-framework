# Data Models Documentation

This document provides architectural guidance on how data structures relate across chains and domains in the Intent Framework. 

For detailed field-by-field documentation, see:

- [Move Intent Framework API Reference](../../docs/move-intent-framework/api-reference.md#type-definitions) - TradeIntent, TradeSession, FungibleAssetLimitOrder
- [Move event structures](../../move-intent-framework/sources/fa_intent.move) - LimitOrderEvent, LimitOrderFulfillmentEvent
- [EVM Escrow documentation](../../docs/evm-intent-framework/README.md)
- [Rust verifier structures](../../trusted-verifier/src/monitor/mod.rs) - IntentEvent, EscrowEvent, FulfillmentEvent, EscrowApproval

## Overview

The Intent Framework uses data structures across three implementation languages (Move, Solidity, Rust) that work together to enable cross-chain escrow operations. This document focuses on:

- **Cross-chain data linking patterns** - How structures link across chains using `intent_id`
- **Event correlation mechanisms** - How verifier normalizes and matches events
- **Domain relationships** - How data structures map to architectural domains
- **State transition patterns** - How data flows between chains

**Key Data Flow Patterns**:

- **Hub Chain (Move)**: Intent creation and fulfillment with event emissions
- **Connected Chains (Move/EVM)**: Escrow creation and release with event emissions
- **Verifier Service (Rust)**: Event monitoring, normalization, and cross-chain validation

## Verification Domain: Normalized Event Structures

The verifier service normalizes blockchain events from different chains into common Rust structures for cross-chain validation. These structures are architectural abstractions that enable the verifier to work with events from both Move and EVM chains.

**Key Normalization Patterns**:

- **IntentEvent** (`trusted-verifier/src/monitor/mod.rs:34-55`) - Normalizes `LimitOrderEvent` from Move hub chain
- **EscrowEvent** (`trusted-verifier/src/monitor/mod.rs:63-86`) - Normalizes `OracleLimitOrderEvent` (Move) and `EscrowInitialized` (EVM) from connected chains
- **FulfillmentEvent** (`trusted-verifier/src/monitor/mod.rs:94-109`) - Normalizes `LimitOrderFulfillmentEvent` from hub chain
- **EscrowApproval** (`trusted-verifier/src/monitor/mod.rs:123-134`) - Cryptographic approval structure for escrow release

**Normalization Purpose**: These structures abstract away chain-specific differences (Move address types vs EVM address types, BCS vs ABI encoding) to enable unified cross-chain validation logic. See [`trusted-verifier/src/monitor/mod.rs`](../../trusted-verifier/src/monitor/mod.rs) for complete field definitions.

## Cross-Chain Data Linking

Data structures link across chains using `intent_id` fields and event correlation patterns.

### Intent ID Pattern

The `intent_id` field serves as the primary cross-chain linking mechanism:

- **Hub Chain Intents**: `intent_id` is set to `intent_address` for regular intents, or a shared address for cross-chain request intents
- **Connected Chain Escrows**: `intent_id` is passed during escrow creation to link back to the hub intent
- **Event Correlation**: Verifier matches events across chains using `intent_id` field

**References**:

- `FungibleAssetLimitOrder.intent_id: Option<address>` - Optional cross-chain linking field
- `LimitOrderEvent.intent_id: address` - Event correlation field
- `EscrowEvent.intent_id: String` - Verifier event matching field

### Reserved Solver Addressing

Solver addresses are preserved across chains:

- **Hub Chain**: `TradeIntent.reservation: Option<IntentReserved>` - Optional reserved solver
- **Connected Chain**: `Escrow.reservedSolver: address` - Always set, never address(0)
- **Verifier Validation**: Validates that fulfillment solver matches reserved solver before approval

### Event Correlation Logic

The verifier correlates events across chains using:

1. **Intent Creation**: `IntentEvent` from hub chain with `intent_id`
2. **Escrow Creation**: `EscrowEvent` from connected chain with matching `intent_id`
3. **Fulfillment**: `FulfillmentEvent` from hub chain with matching `intent_id`
4. **Approval**: `EscrowApproval` generated after validation, linked by `intent_id`

## Serialization Formats

Data structures are serialized differently depending on the chain and communication protocol:

- **Move Contracts**: BCS (Binary Canonical Serialization) for on-chain storage
- **EVM Contracts**: ABI encoding for Solidity structs
- **Verifier Service**: JSON for REST API communication, base64 for signature encoding
- **Cross-Chain Events**: JSON serialization for event data passed between chains

## State Transitions

Key data structure state transitions:

1. **Intent Creation**: `TradeIntent` created → `LimitOrderEvent` emitted
2. **Escrow Creation**: `Escrow` created → `EscrowEvent` emitted (linked via `intent_id`)
3. **Intent Fulfillment**: `TradeIntent` consumed → `LimitOrderFulfillmentEvent` emitted
4. **Escrow Approval**: `EscrowApproval` generated → `Escrow.isClaimed` set to true
5. **Escrow Release**: `Escrow` funds transferred to `reservedSolver`
