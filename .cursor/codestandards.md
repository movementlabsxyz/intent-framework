# Coding Standards

This document outlines coding standards and conventions for the Intent Framework project.

## Move/Aptos

- Use `snake_case` for function and variable names
- Use `PascalCase` for struct names
- Use witness types for type-safe validation
- Emit events for all state changes that need external monitoring
- **Formatting**: Use `aptos move fmt` for consistent code formatting (requires `aptos update movefmt` first)
- **Style Guide**: Follow Aptos style guide: <https://aptos.dev/guides/move-guides/style-guide>
- **Configuration**: Consider adding `.aptos/config.yaml` for formatting options

## Solidity

- Follow Solidity style guide (PascalCase for contracts, camelCase for functions)
- Use `require()` statements for validation with clear error messages
- Emit events for all state changes
- **Formatting**: Use `prettier-plugin-solidity` or `forge fmt` (if using Foundry)
- **Style Guide**: Follow Solidity Style Guide: <https://docs.soliditylang.org/en/latest/style-guide.html>
- **Configuration**: Consider adding `.prettierrc` or `foundry.toml` with formatting rules

## Rust

- Follow Rust naming conventions (snake_case for functions/variables, PascalCase for types)
- Use `anyhow::Result` for error handling
- Use structured logging with appropriate log levels
- Separate concerns: monitoring, validation, and crypto operations in separate modules
- **Formatting**: Use `rustfmt` (default settings) for consistent code formatting
- **Linting**: Use `clippy` for additional linting (already configured in `rust-toolchain.toml`)
- **CI**: Consider adding `cargo fmt --check` to CI pipeline to enforce formatting
- **Configuration**: Add `rustfmt.toml` if custom formatting rules are needed

## Shell Scripts

- Use `set -e` to exit on errors
- Source utility scripts: `. "$(dirname "$0")/../util.sh"`
- Use `log()` function for consistent logging
- Check for required environment variables early
- Use `get_profile_address()` for Aptos address extraction
