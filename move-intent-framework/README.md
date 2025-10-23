# Move Intent Framework

A framework for creating conditional trading intents. This framework enables users to create time-bound, conditional offers that can be executed by third parties when specific conditions are met. It provides a generic system for creating tradeable intents with built-in expiry, witness validation, and owner revocation capabilities, enabling sophisticated trading mechanisms like limit orders and conditional swaps.

This framework integrates with the blockchain's native fungible asset standard and transaction processing system.

For detailed technical specifications and design rationale, see [AIP-511: Aptos Intent Framework](https://github.com/aptos-foundation/AIPs/pull/511).

## Quick Start

### Basic Usage

1. **Create an Intent**: Lock your assets with trading conditions
2. **Broadcast**: The contract emits events for solvers to discover
3. **Execute**: Solvers fulfill the conditions and complete the trade

For detailed flow descriptions and implementation details, see:
- [Technical Overview](docs/technical-overview.md) - Architecture and intent flows
- [API Reference](docs/api-reference.md) - Complete API documentation
- [Intent Reservation](docs/intent-reservation.md) - Reserved intent implementation
- [Oracle Intents](docs/oracle-intents.md) - Oracle-guarded intent implementation
- [Intent as Escrow](docs/intent-as-escrow.md) - How the intent system functions as an escrow mechanism

## Development

### Prerequisites

- [Nix](https://nixos.org/download.html) package manager
- CLI tools (automatically provided via [aptos.nix](../aptos.nix))

### Getting Started

1. **Enter Development Environment**
   ```bash
   nix-shell  # Uses [shell.nix](shell.nix)
   ```

2. **Run Tests**
   ```bash
   test  # Auto-runs tests on file changes
   ```

For complete development setup, testing, and configuration details, see [Development Guide](docs/development.md).

## Project Structure

```
move-intent-framework/
├── README.md                    # This overview
├── docs/                        # Comprehensive documentation
│   ├── technical-overview.md    # Architecture and intent flows
│   ├── api-reference.md         # Complete API documentation
│   ├── development.md          # Development setup and testing
│   ├── intent-reservation.md   # Reservation system details
│   ├── oracle-intents.md       # Oracle-guarded intent details
│   └── intent-as-escrow.md     # Intent system as escrow mechanism
├── sources/                    # Move modules
│   ├── intent.move            # Core generic intent framework
│   ├── fa_intent.move         # Fungible asset implementation
│   ├── fa_intent_with_oracle.move # Oracle-based implementation
│   └── intent_reservation.move # Reservation system
├── tests/                      # Test modules
├── Move.toml                   # Package configuration
└── shell.nix                  # Development environment
```
