# Intent Framework

A framework for creating conditional trading intents. This repository contains the Move modules and documentation for implementing time-bound, conditional offers that can be executed by third parties when specific conditions are met.

## Project Structure

```
intent-framework/
├── README.md                    # Detailed framework documentation
├── docs/
│   └── intent-reservation.md    # Reservation system implementation details
├── sources/                     # Move modules
│   ├── intent.move             # Core generic intent framework
│   ├── fa_intent.move          # Fungible asset implementation
│   └── intent_reservation.move # Reservation system
├── tests/                       # Test modules
└── Move.toml                   # Package configuration
```

## Quick Start

For detailed documentation, API reference, and development setup, see the [intent-framework README](intent-framework/README.md).

### Intent Types

The framework supports two types of intents:

- **Unreserved**: Anyone can solve the intent after it's created
- **Reserved**: Only a specific solver (chosen off-chain) can solve the intent

For detailed flow descriptions and implementation details, see [intent-framework/README.md](intent-framework/README.md) and [intent-framework/docs/intent-reservation.md](intent-framework/docs/intent-reservation.md).

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
