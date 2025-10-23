# Move Intent Framework

A framework for creating conditional trading intents. This framework enables users to create time-bound, conditional offers that can be executed by third parties when specific conditions are met. It provides a generic system for creating tradeable intents with built-in expiry, witness validation, and owner revocation capabilities, enabling sophisticated trading mechanisms like limit orders and conditional swaps.

This framework integrates with the blockchain's native fungible asset standard and transaction processing system.

For detailed technical specifications and design rationale, see [AIP-511: Aptos Intent Framework](https://github.com/aptos-foundation/AIPs/pull/511).

## 🔒 Security Requirements

### Critical: Escrow Intent Revocation Control

**⚠️ ESCROW INTENTS MUST ALWAYS BE CREATED AS NON-REVOCABLE ⚠️**

This is a **FUNDAMENTAL** security requirement for any escrow system:

1. **Escrow funds MUST be locked** and cannot be withdrawn by the user
2. **Funds can ONLY be released** by verifier approval or rejection  
3. **The `revocable` parameter MUST ALWAYS be set to `false`** when creating escrow intents
4. **Any verifier implementation MUST verify** that escrow intents are non-revocable
5. **This ensures verifiers can safely trigger actions elsewhere** based on deposit events

**FAILURE TO ENSURE NON-REVOCABLE ESCROW INTENTS COMPLETELY DEFEATS THE PURPOSE OF AN ESCROW SYSTEM AND CREATES A CRITICAL SECURITY VULNERABILITY.**

✅ **Current implementation**: ESCROW INTENTS ARE CREATED AS NON-REVOCABLE (`revocable = false`)

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
   nix-shell  # Uses [shell.nix](shell.nix)
   ```

2. **Run Tests**
   ```bash
   test  # Auto-runs tests on file changes
   ```

### Deployment

Deploy the Intent Framework to an Aptos network:

```bash
# 1. Setup local chain (optional)
./infra/setup-docker/setup-docker-chain.sh

# 2. Configure Aptos CLI to use local chain (port 8080)
aptos init --profile local --network local

# 3. Enter dev environment
nix-shell

# 4. Deploy to current network
pub  # This runs: aptos move publish --named-addresses aptos_intent=$intent

# 5. Verify deployment
aptos move test --dev
```

**Note**: The `pub` command deploys to whatever network your Aptos CLI is configured for. For local development, you must first configure Aptos CLI to point to your local Docker chain (port 8080) using `aptos init --profile local --network local`.

**Multiple chains**: If you have multiple chains running (e.g., port 8080 and 8082), you can create separate profiles:
```bash
# Chain 1 (port 8080)
aptos init --profile local --network local

# Chain 2 (port 8082) 
aptos init --profile local2 --network local --rest-url http://127.0.0.1:8082

# Deploy to specific chain
aptos move publish --profile local --named-addresses aptos_intent=0x<your_address>
aptos move publish --profile local2 --named-addresses aptos_intent=0x<your_address>
```

**Manual deployment:**
```bash
# Get your account address
aptos config show-profiles | jq -r '.Result.default.account'

# Deploy with your address
aptos move publish --named-addresses aptos_intent=0x<your_address>
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
│   ├── intent_as_escrow.move  # Simplified escrow abstraction
│   └── intent_reservation.move # Reservation system
├── tests/                      # Test modules
├── Move.toml                   # Package configuration
└── shell.nix                  # Development environment
```
