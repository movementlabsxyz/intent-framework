# Development Guide

This document covers development setup, testing, configuration, and dependencies for the Intent Framework.

## Development Setup

### Prerequisites

- [Nix](https://nixos.org/download.html) package manager
- CLI tools (automatically provided via [aptos.nix](../../aptos.nix))

### Getting Started

1. **Enter Development Environment**

   ```bash
   nix-shell  # Uses [shell.nix](shell.nix)
   ```

2. **Run Tests**

   ```bash
   test  # Auto-runs tests on file changes
   ```

## Testing

### Running Tests

Run all tests with:
```bash
aptos move test --dev --named-addresses aptos_intent=0x123
```

### Test Structure

The test suite includes:

- **Core Intent Tests**: [`intent_tests.move`](../tests/intent_tests.move) - Tests for the base intent framework
- **Fungible Asset Tests**: [`fa_tests.move`](../tests/fa_tests.move) - Tests for fungible asset trading
- **Reservation Tests**: [`intent_reservation_tests.move`](../tests/intent_reservation_tests.move) - Tests for the reservation system
- **Oracle Tests**: [`fa_intent_with_oracle_tests.move`](../tests/fa_intent_with_oracle_tests.move) - Tests for oracle-based intents
- **Entry Flow Tests**: [`fa_entryflow_tests.move`](../tests/fa_entryflow_tests.move) - Tests for complete intent flows
- **Test Utilities**: [`fa_test_utils.move`](../tests/fa_test_utils.move) - Shared test helper functions

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
aptos move test --dev --named-addresses aptos_intent=0x123 --filter intent_tests

# Run only fungible asset tests
aptos move test --dev --named-addresses aptos_intent=0x123 --filter fa_tests

# Run only reservation tests
aptos move test --dev --named-addresses aptos_intent=0x123 --filter intent_reservation_tests
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
aptos_intent = "_"

[dev-addresses]
aptos_intent = "0x123"

[dependencies.AptosFramework]
git = "https://github.com/aptos-labs/aptos-framework.git"
rev = "mainnet"
subdir = "aptos-framework"
```

**Key Configuration:**
- **Package Name**: `aptos-intent`
- **Address**: Uses `_` for deployment flexibility
- **Dev Address**: `0x123` for testing
- **Dependencies**: Aptos Framework from mainnet branch

### shell.nix

The [`shell.nix`](../shell.nix) file provides:

- **Development Environment**: Nix-based reproducible environment
- **Convenient Aliases**: Short commands for common tasks
- **Tool Versions**: Specific versions of development tools

**Available Commands:**
- `test` - Run tests with auto-reload
- `build` - Build the project
- `fmt` - Format code
- `lint` - Run linters

## Dependencies

### Aptos Framework

- **Source**: [Aptos Framework](https://github.com/aptos-labs/aptos-framework)
- **Branch**: `mainnet`
- **Purpose**: Core blockchain functionality, fungible assets, cryptography

### Aptos CLI

- **Version**: v4.3.0
- **Source**: Defined in [aptos.nix](../../aptos.nix)
- **Purpose**: Development, testing, and deployment

### Key Framework Modules Used

- `aptos_framework::object` - Object management
- `aptos_framework::fungible_asset` - Fungible asset operations
- `aptos_framework::primary_fungible_store` - Primary storage
- `aptos_std::ed25519` - Cryptographic signatures
- `aptos_std::signer` - Signer utilities
- `aptos_std::timestamp` - Time management

## Development Workflow

### 1. Making Changes

1. Enter the development environment: `nix-shell`
2. Make your changes to source files
3. Tests run automatically on file changes
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
