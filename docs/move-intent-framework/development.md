# Development Guide

This document covers development setup, testing, configuration, and dependencies for the Intent Framework.

## Development Setup

### Prerequisites

- [Nix](https://nixos.org/download.html) package manager
- CLI tools (automatically provided via [aptos.nix](../../aptos.nix))

### Getting Started

1. **Enter Development Environment**

   ```bash
   # From project root
   nix develop
   ```

2. **Run Tests**

   ```bash
   # From project root
   nix develop -c bash -c "cd move-intent-framework && aptos move test --dev --named-addresses mvmt_intent=0x123"
   ```

## Testing

### Running Tests

Run all tests with:
```bash
aptos move test --dev --named-addresses mvmt_intent=0x123
```

### Test Structure

The test suite includes:

- **Core Intent Tests**: [`intent_tests.move`](../../move-intent-framework/tests/intent_tests.move) - Tests for the base intent framework
- **Fungible Asset Tests**: [`fa_tests.move`](../../move-intent-framework/tests/fa_tests.move) - Tests for fungible asset trading
- **Reservation Tests**: [`intent_reservation_tests.move`](../../move-intent-framework/tests/intent_reservation_tests.move) - Tests for the reservation system
- **Oracle Tests**: [`fa_intent_with_oracle_tests.move`](../../move-intent-framework/tests/fa_intent_with_oracle_tests.move) - Tests for oracle-based intents
- **Entry Flow Tests**: [`fa_entryflow_tests.move`](../../move-intent-framework/tests/fa_entryflow_tests.move) - Tests for complete intent flows
- **Test Utilities**: [`fa_test_utils.move`](../../move-intent-framework/tests/fa_test_utils.move) - Shared test helper functions

### Test Categories

1. **Basic Intent Creation**: Tests creating unreserved intents
2. **Reserved Intent Flow**: Tests the complete reservation workflow
3. **Signature Verification**: Tests Ed25519 signature verification
4. **Expiry Handling**: Tests intent expiration behavior
5. **Error Conditions**: Tests various error scenarios
6. **Cross-Module Integration**: Tests interactions between modules

### Running Specific Tests

```bash
# Run only intent tests
aptos move test --dev --named-addresses mvmt_intent=0x123 --filter intent_tests

# Run only fungible asset tests
aptos move test --dev --named-addresses mvmt_intent=0x123 --filter fa_tests

# Run only reservation tests
aptos move test --dev --named-addresses mvmt_intent=0x123 --filter intent_reservation_tests
```

## Configuration

### Move.toml

The [`Move.toml`](../Move.toml) file contains:

```toml
[package]
name = "aptos-intent"
version = "1.0.0"
authors = []

[addresses]
mvmt_intent = "_"

[dev-addresses]
mvmt_intent = "0x123"

[dependencies.AptosFramework]
git = "https://github.com/aptos-labs/aptos-framework.git"
rev = "<commit-hash>"  # See Move.toml for the actual pinned commit
subdir = "aptos-framework"
```

**Key Configuration:**
- **Package Name**: `aptos-intent`
- **Address**: Uses `_` for deployment flexibility
- **Dev Address**: `0x123` for testing
- **Dependencies**: Aptos Framework pinned to a specific commit (see `Move.toml` for the exact commit hash)

### Development Environment

The development environment is provided via the root [`flake.nix`](../../flake.nix), which includes:
- Rust toolchain
- Aptos CLI (via [`aptos.nix`](../../aptos.nix))
- Node.js and npm
- Other development tools

Enter the environment with `nix develop` from the project root.

## Dependencies

### Aptos Framework

- **Source**: [Aptos Framework](https://github.com/aptos-labs/aptos-framework)
- **Version**: Pinned to a specific commit hash (see `Move.toml` for the exact commit)
- **Purpose**: Core blockchain functionality, fungible assets, cryptography

### Aptos CLI

- **Source**: Defined in [aptos.nix](../../aptos.nix) (version is managed there)
- **Purpose**: Development, testing, and deployment

### Key Framework Modules Used

- `aptos_framework::object` - Object management
- `aptos_framework::fungible_asset` - Fungible asset operations
- `aptos_framework::primary_fungible_store` - Primary storage
- `aptos_std::ed25519` - Cryptographic signatures
- `aptos_std::signer` - Signer utilities
- `aptos_std::timestamp` - Time management

## Deployment

### Local Chain Setup

Deploy the Intent Framework to a local Move VM network:

```bash
# 1. Setup local chain (optional)
./testing-infra/chain-connected-mvm/setup-chain.sh

# 2. Configure Aptos CLI to use local chain (port 8080)
aptos init --profile local --network local

# 3. Enter dev environment (from project root)
nix develop

# 4. Deploy to current network
# Get your account address
INTENT=$(aptos config show-profiles | jq -r '.Result.default.account')
# Deploy
aptos move publish --named-addresses mvmt_intent=0x$INTENT --skip-fetch-latest-git-deps

# 5. Verify deployment
aptos move test --dev --named-addresses mvmt_intent=0x123
```

**Note**: The deploy command publishes to whatever network your Aptos CLI is configured for. For local development, you must first configure Aptos CLI to point to your local Docker chain (port 8080) using `aptos init --profile local --network local`.

### Multiple Chains

If you have multiple chains running (e.g., port 8080 and 8082), you can create separate profiles:

```bash
# Chain 1 (port 8080)
aptos init --profile local --network local

# Chain 2 (port 8082) 
aptos init --profile local2 --network local --rest-url http://127.0.0.1:8082

# Deploy to specific chain
aptos move publish --profile local --named-addresses mvmt_intent=0x<your_address>
aptos move publish --profile local2 --named-addresses mvmt_intent=0x<your_address>
```

### Manual Deployment

```bash
# Get your account address
aptos config show-profiles | jq -r '.Result.default.account'

# Deploy with your address
aptos move publish --named-addresses mvmt_intent=0x<your_address> --skip-fetch-latest-git-deps
```

## Development Workflow

### 1. Making Changes

1. Enter the development environment: `nix develop` (from project root)
2. Make your changes to source files
3. Run tests to verify changes
4. Fix any test failures
5. Commit your changes

### 2. Adding New Features

1. **Design**: Plan the feature and its integration points
2. **Implementation**: Add the core functionality
3. **Tests**: Write comprehensive tests
4. **Documentation**: Update relevant documentation
5. **Review**: Ensure all tests pass and code is clean

### 3. Debugging

- **Test Failures**: Check test output for specific error messages
- **Compilation Errors**: Use `aptos move compile` to check syntax
- **Runtime Errors**: Add debug prints or use Move debugger
- **Signature Issues**: Verify signature format and verification logic

## Code Style

### Move Code Conventions

- Use descriptive function and variable names
- Add comprehensive documentation comments
- Follow Move's naming conventions (snake_case)
- Use appropriate visibility modifiers (`public`, `public(friend)`, `public(script)`)

### Test Conventions

- Test both success and failure cases
- Use descriptive test function names
- Group related tests logically
- Include setup and teardown as needed

## Troubleshooting

### Common Issues

1. **Compilation Errors**
   - Check import statements
   - Verify function signatures
   - Ensure proper type constraints

2. **Test Failures**
   - Verify test setup and teardown
   - Check for timing issues
   - Ensure proper resource management

3. **Signature Verification Issues**
   - Verify signature format (64 bytes)
   - Check public key extraction
   - Ensure consistent data hashing

### Getting Help

- Check the [API Reference](api-reference.md) for function signatures
- Review [Technical Overview](technical-overview.md) for architecture
- Examine existing tests for usage examples
- Consult Aptos documentation for framework-specific issues
