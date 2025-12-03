# Intent Framework Documentation

## Overview

A framework for creating conditional trading intents. Supports single-chain intents (unreserved, reserved, oracle-guarded) and cross-chain intents (inflow with escrows, outflow with transfers). For cross-chain operations, a verifier service monitors both chains to provide approval signatures.

## Getting Started

- **[Protocol overview](protocol.md)** - Cross-chain intent system flows and sequence diagrams
- **[Documentation Guide](docs-guide.md)** - Documentation structure and navigation

## Components

- **[Move Intent Framework](move-intent-framework/README.md)** - Move contracts for intents and escrows
- **[EVM Intent Framework](evm-intent-framework/README.md)** - Solidity contracts for EVM escrows
- **[Trusted Verifier](trusted-verifier/README.md)** - Chain monitoring and approval signature service
- **[Solver Tools](solver/README.md)** - Solver service and tools for automatic signature generation and transaction templates
- **[Testing Infrastructure](testing-infra/README.md)** - Chain setup and testing infrastructure
