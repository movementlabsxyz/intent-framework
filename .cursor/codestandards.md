# Coding Standards

This document outlines coding standards and conventions for the Intent Framework project.

## Move/Aptos

- Use `snake_case` for function and variable names
- Use `PascalCase` for struct names
- Use witness types for type-safe validation
- Emit events for all state changes that need external monitoring

## Solidity

- Follow Solidity style guide (PascalCase for contracts, camelCase for functions)
- Use `require()` statements for validation with clear error messages
- Emit events for all state changes

## Rust

- Follow Rust naming conventions (snake_case for functions/variables, PascalCase for types)
- Use `anyhow::Result` for error handling
- Use structured logging with appropriate log levels
- Separate concerns: monitoring, validation, and crypto operations in separate modules

## Shell Scripts

- Use `set -e` to exit on errors
- Source utility scripts: `. "$(dirname "$0")/../util.sh"`
- Use `log()` function for consistent logging
- Check for required environment variables early
- Use `get_profile_address()` for Aptos address extraction

