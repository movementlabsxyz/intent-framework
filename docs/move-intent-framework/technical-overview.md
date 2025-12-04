# Technical Overview

This document provides a comprehensive technical overview of the Intent Framework, including the intent flow, core components, and architectural design.

## Intent Flow

The framework supports three types of intents:

#### Unreserved Intent Flow

1. **Intent Creator creates intent**: Locks on-chain resources with specific trading conditions and expiry time.
2. **Intent broadcast**: The contract emits an event containing the trading details that any solver can monitor.
3. **Any Solver execution**: In a single transaction, any solver:
   - Calls `start_intent_session()` to begin fulfilling the intent
   - Meets the intent's trading conditions (e.g., obtains the wanted fungible asset).
   - Calls `finish_intent_session()` with the required witness to complete the intent.

#### Reserved Intent Flow

**Why reserved intents?** For cross-chain trading, solvers need guarantees that intent creators won't switch to another solver after the solver has committed resources on other chains. Reserved intents provide this commitment.

1. **Off-chain negotiation**: Intent creator shares intent details with a specific solver.
2. **Solver authorization**: Solver signs the intent hash off-chain and returns signature to creator.
3. **Intent Creator creates reserved intent**: Locks resources with solver address and signature.
4. **Intent broadcast**: Contract emits event, but only the authorized solver can execute.
5. **Authorized Solver execution**: Only the pre-authorized solver can call `start_intent_session()` and complete the intent.

#### Oracle-Guarded Intent Flow

**Why oracle-guarded intents?** For conditional trading based on external data (such as price feeds), intents need to verify oracle-reported values before execution. Oracle-guarded intents provide this external data validation.

1. **Intent Creator creates oracle-guarded intent**: Locks resources with oracle requirements (minimum value threshold and authorized oracle public key).
2. **Intent broadcast**: Contract emits event with oracle requirements for solvers to monitor.
3. **Solver obtains oracle signature**: Solver gets signed data from the authorized oracle.
4. **Solver execution with oracle witness**: Solver calls `start_intent_session()` and provides oracle signature witness proving the reported value meets the threshold.
5. **Contract verifies oracle signature**: Contract verifies the oracle signature and checks that the reported value meets the minimum threshold.
6. **Intent completion**: If verification succeeds, the intent executes; otherwise, the transaction aborts.

For detailed implementation details of the oracle system, see [oracle-intents](oracle-intents.md).

## Core Components

This directory contains the core Move modules that implement the Intent Framework.

### Modules

#### 1. Base Intent Module

[`intent.move`](../../move-intent-framework/sources/intent.move) - The core generic framework that defines the fundamental intent system. This module provides the abstract structures and functions for creating, managing, and executing any type of conditional trade intent.

- **Intent<Source, Args>**: Stores the offered resource, trade conditions, expiry time, and witness type requirements. Acts as the immutable record of what someone wants to trade.
- **Session<Args>**: Created when someone starts an intent session. Contains the trade conditions and witness requirements, allowing the session opener to fulfill the trade.
- **Witness System**: Enforces unlock conditions through Move's type system. The witness is an empty struct that can only be created by functions that first verify the trading conditions. For example, `FungibleAssetRecipientWitness` can only be created after confirming the received asset matches the wanted type and amount.

  *Note: The witness is empty (not a flag like `verified: true`) because anyone could forge a flag, but only the verification function can create the specific witness type. Having the witness proves you went through the proper verification process.*

#### 2. Implementation for Fungible Asset

[`fa_intent.move`](../../move-intent-framework/sources/fa_intent.move) - A concrete implementation of the intent framework specifically designed for fungible asset trading. This module handles the creation and execution of limit orders between different fungible assets.

- **FungibleAssetLimitOrder**: Defines the specific trade parameters (desired token metadata, amount, requester, chain IDs) for fungible asset limit orders.
- **LimitOrderEvent**: Emits events when intents are created, providing transparency and allowing external systems to discover available trades.
- **Primary Fungible Store Integration**: Handles the actual transfer of fungible assets using the blockchain's primary fungible store system for seamless asset management.

#### 3. Intent Reservation System

[`intent_reservation.move`](../../move-intent-framework/sources/intent_reservation.move) - Provides the reservation system for reserved intents, including signature verification and solver authorization.

- **Draftintent**: Off-chain data structure for sharing intent details without solver information.
- **IntentToSign**: Data structure that solvers sign to commit to solving a specific intent.
- **IntentReserved**: On-chain reservation data that restricts intent execution to authorized solvers.

#### 4. Oracle-Guarded Intent System

[`fa_intent_with_oracle.move`](../../move-intent-framework/sources/fa_intent_with_oracle.move) - Extends the fungible asset intent flow with oracle signature requirements for conditional execution based on external data.

- **OracleSignatureRequirement**: Defines minimum reported values and authorized oracle public keys.
- **OracleGuardedLimitOrder**: Trading conditions that include oracle requirements.
- **OracleSignatureWitness**: Proof that an oracle has signed off on external data with a value meeting the threshold.
- **OracleLimitOrderEvent**: Specialized events that include oracle requirements for transparency.

## Architecture Design

The Intent Framework is designed with the following principles:

1. **Generic and Extensible**: The base intent module provides abstract structures that can be implemented for any type of conditional trade.
2. **Type-Safe Witness System**: Uses Move's type system to ensure proper verification before intent completion.
3. **Event-Driven**: Emits events for external systems to discover and monitor available intents.
4. **Reservation Support**: Enables off-chain negotiation and solver commitment for complex trading scenarios.
5. **Expiry Management**: Built-in time-bound execution with automatic cleanup of expired intents.

For detailed technical specifications and design rationale, see [AIP-511: Aptos Intent Framework](https://github.com/aptos-foundation/AIPs/pull/511).
