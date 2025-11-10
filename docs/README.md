# Intent Framework Documentation

## Overview

The Intent Framework enables cross-chain escrow operations with verifier-based approval. Intents are created on a hub chain, escrows are created on connected chains, and a verifier service monitors both chains to provide approval signatures.

## Getting Started

- **[Cross-Chain Flow](cross-chain-flow.md)** - Overview of the cross-chain intent and escrow flow with sequence diagrams
- **[Documentation Guide](docs-guide.md)** - How to navigate and understand the documentation structure

## Components

- **[Move Intent Framework](move-intent-framework/README.md)** - Aptos Move contracts for intents and escrows
- **[EVM Intent Framework](evm-intent-framework/README.md)** - Solidity contracts for EVM escrows
- **[Trusted Verifier](trusted-verifier/README.md)** - Service that monitors chains and provides approval signatures
- **[Testing Infrastructure](testing-infra/README.md)** - Infrastructure setup for running chains for development and testing
