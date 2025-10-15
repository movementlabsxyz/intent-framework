# Intent Framework

A framework for creating conditional trading intents. This framework enables users to create time-bound, conditional offers that can be executed by third parties when specific conditions are met. It provides a generic system for creating tradeable intents with built-in expiry, witness validation, and owner revocation capabilities, enabling sophisticated trading mechanisms like limit orders and conditional swaps.

This framework integrates with the blockchain's native fungible asset standard and transaction processing system.

For detailed technical specifications and design rationale, see [AIP-511: Aptos Intent Framework](https://github.com/aptos-foundation/AIPs/pull/511).

## Intent Flow

The framework supports two types of intents:

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

For detailed implementation details of the reservation system, see [docs/intent-reservation.md](docs/intent-reservation.md).

## Core Components

This directory contains the core Move modules that implement the Intent Framework.

### Modules

#### 1. Base Intent Module

[`intent.move`](sources/intent.move) - The core generic framework that defines the fundamental intent system. This module provides the abstract structures and functions for creating, managing, and executing any type of conditional trade intent.

- **TradeIntent<Source, Args>**: Stores the offered resource, trade conditions, expiry time, and witness type requirements. Acts as the immutable record of what someone wants to trade.
- **TradeSession<Args>**: Created when someone starts an intent session. Contains the trade conditions and witness requirements, allowing the session opener to fulfill the trade.
- **Witness System**: Enforces unlock conditions through Move's type system. The witness is an empty struct that can only be created by functions that first verify the trading conditions. For example, `FungibleAssetRecipientWitness` can only be created after confirming the received asset matches the wanted type and amount.

  *Note: The witness is empty (not a flag like `verified: true`) because anyone could forge a flag, but only the verification function can create the specific witness type. Having the witness proves you went through the proper verification process.*

#### 2. Implementation for Fungible Asset

[`fa_intent.move`](sources/fa_intent.move) - A concrete implementation of the intent framework specifically designed for fungible asset trading. This module handles the creation and execution of limit orders between different fungible assets.

- **FungibleAssetLimitOrder**: Defines the specific trade parameters (wanted token type, amount, issuer) for fungible asset limit orders.
- **LimitOrderEvent**: Emits events when intents are created, providing transparency and allowing external systems to discover available trades.
- **Primary Fungible Store Integration**: Handles the actual transfer of fungible assets using the blockchain's primary fungible store system for seamless asset management.

#### 3. Intent Reservation System

[`intent_reservation.move`](sources/intent_reservation.move) - Provides the reservation system for reserved intents, including signature verification and solver authorization.

- **IntentDraft**: Off-chain data structure for sharing intent details without solver information.
- **IntentToSign**: Data structure that solvers sign to commit to solving a specific intent.
- **IntentReserved**: On-chain reservation data that restricts intent execution to authorized solvers.

## API Reference

#### Creating an Intent

```move
public fun create_intent<Source: store, Args: store + drop, Witness: drop>(
    offered_resource: Source,
    argument: Args,
    expiry_time: u64,
    issuer: address,
    _witness: Witness,
): Object<TradeIntent<Source, Args>>
```

#### Starting a Trading Session

```move
public fun start_intent_session<Source: store, Args: store + drop>(
    intent: Object<TradeIntent<Source, Args>>,
): (Source, TradeSession<Args>)
```

#### Completing an Intent

```move
public fun finish_intent_session<Witness: drop, Args: store + drop>(
    session: TradeSession<Args>,
    _witness: Witness,
)
```

## Development Setup

#### Prerequisites

- [Nix](https://nixos.org/download.html) package manager
- CLI tools (automatically provided via [aptos.nix](../aptos.nix))

#### Getting Started

1. **Enter Development Environment**

   ```bash
   nix-shell  # Uses [shell.nix](shell.nix)
   ```

2. **Run Tests**

   ```bash
   test  # Auto-runs tests on file changes
   ```

## Testing

Run tests with:
```bash
aptos move test --dev
```

## Configuration

- [`Move.toml`](Move.toml) - Move package configuration with dependencies and addresses
- [`shell.nix`](shell.nix) - Development environment setup with convenient aliases

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](../LICENSE) file for details.

## Dependencies

- [Aptos Framework](https://github.com/aptos-labs/aptos-framework) (mainnet branch) - configured in [Move.toml](Move.toml)
- Aptos CLI v4.3.0 - defined in [aptos.nix](../aptos.nix)
