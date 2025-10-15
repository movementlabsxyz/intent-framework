# Intent Framework

A framework for creating conditional trading intents. This framework enables users to create time-bound, conditional offers that can be executed by third parties when specific conditions are met. It provides a generic system for creating tradeable intents with built-in expiry, witness validation, and owner revocation capabilities, enabling sophisticated trading mechanisms like limit orders and conditional swaps.

This framework integrates with [Aptos Core](https://github.com/aptos-labs/aptos-core) as Move modules that leverage the blockchain's native fungible asset standard and transaction processing system.

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

For detailed implementation details of the reservation system, see [intent-framework/docs/intent-reservation.md](intent-framework/docs/intent-reservation.md).

## Development Setup

#### Prerequisites

- [Nix](https://nixos.org/download.html) package manager
- Aptos CLI (automatically provided via [aptos.nix](aptos.nix))

#### Getting Started

1. **Enter Development Environment**

   ```bash
   cd intent-framework
   nix-shell  # Uses [shell.nix](intent-framework/shell.nix)
   ```

2. **Run Tests**

   ```bash
   test  # Auto-runs tests on file changes
   ```

3. **Publish Module**

   ```bash
   pub  # Publishes to Aptos network
   ```

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

## Testing

Run tests with:
```bash
cd intent-framework
aptos move test --dev
```

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Dependencies

- [Aptos Framework](https://github.com/aptos-labs/aptos-framework) (mainnet branch) - configured in [Move.toml](intent-framework/Move.toml)
- Aptos CLI v4.3.0 - defined in [aptos.nix](aptos.nix)
