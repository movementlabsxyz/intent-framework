# Move Intent Framework

A framework for creating conditional trading intents with time-bound, conditional offers that can be executed by third parties. Provides a generic system for tradeable intents with expiry, witness validation, and revocation capabilities.

Inspired by [AIP-511: Aptos Intent Framework](https://github.com/aptos-foundation/AIPs/pull/511).

## Quick Start

See the [component README](../../move-intent-framework/README.md) for quick start commands.

## Documentation

For detailed flow descriptions and implementation details, see:

- [Technical Overview](technical-overview.md) - Architecture and intent flows
- [API Reference](api-reference.md) - Complete API documentation
- [Development Guide](development.md) - Development setup and testing
- [Intent Reservation](intent-reservation.md) - Reserved intent implementation
- [Oracle Intents](oracle-intents.md) - Oracle-guarded intent implementation
- [Intent as Escrow](intent-as-escrow.md) - How the intent system functions as an escrow mechanism

## Project Structure

```text
move-intent-framework/
├── sources/          # Move modules (intent.move, fa_intent.move, etc.)
├── tests/            # Test modules
└── Move.toml         # Package configuration
```
