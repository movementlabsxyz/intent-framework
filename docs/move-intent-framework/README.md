# Move Intent Framework

A framework for creating conditional trading intents. This framework enables users to create time-bound, conditional offers that can be executed by third parties when specific conditions are met. It provides a generic system for creating tradeable intents with built-in expiry, witness validation, and owner revocation capabilities, enabling sophisticated trading mechanisms like limit orders and conditional swaps.

This framework integrates with the blockchain's native fungible asset standard and transaction processing system.

For detailed technical specifications and design rationale, see [AIP-511: Aptos Intent Framework](https://github.com/aptos-foundation/AIPs/pull/511).

### Verifier Implementation Requirements

When implementing verifiers for escrow systems:

- **Always verify** that escrow intents have `revocable = false`
- **Reject any escrow intent** that allows user revocation
- **Document this requirement** in your verifier implementation
- **Test thoroughly** to ensure revocation is impossible

## Quick Start

For quick start instructions, see the [component README](../../move-intent-framework/README.md).

## Documentation

For detailed flow descriptions and implementation details, see:
- [Technical Overview](technical-overview.md) - Architecture and intent flows
- [API Reference](api-reference.md) - Complete API documentation
- [Development Guide](development.md) - Development setup and testing
- [Intent Reservation](intent-reservation.md) - Reserved intent implementation
- [Oracle Intents](oracle-intents.md) - Oracle-guarded intent implementation
- [Intent as Escrow](intent-as-escrow.md) - How the intent system functions as an escrow mechanism

## Project Structure

```
move-intent-framework/
├── sources/                    # Move modules
│   ├── intent.move            # Core generic intent framework
│   ├── fa_intent.move         # Fungible asset implementation
│   ├── fa_intent_with_oracle.move # Oracle-based implementation
│   ├── intent_as_escrow.move  # Simplified escrow abstraction
│   └── intent_reservation.move # Reservation system
├── tests/                      # Test modules
└── Move.toml                   # Package configuration

Documentation is located in docs/move-intent-framework/:
├── README.md                    # This overview
├── technical-overview.md        # Architecture and intent flows
├── api-reference.md            # Complete API documentation
├── development.md              # Development setup and testing
├── intent-reservation.md       # Reservation system details
├── oracle-intents.md           # Oracle-guarded intent details
└── intent-as-escrow.md         # Intent system as escrow mechanism
```
