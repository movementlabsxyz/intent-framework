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
   # From project root
   nix develop
   ```

2. **Run Tests**
   ```bash
   # From project root
   nix develop -c bash -c "cd move-intent-framework && aptos move test --dev --named-addresses aptos_intent=0x123"
   ```

For complete development setup, testing, deployment, and configuration details, see [Development Guide](docs/development.md).

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
│   ├── intent_as_escrow.move  # Simplified escrow abstraction
│   └── intent_reservation.move # Reservation system
├── tests/                      # Test modules
└── Move.toml                   # Package configuration
```
