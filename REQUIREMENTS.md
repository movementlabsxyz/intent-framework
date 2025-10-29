# Requirements Document

## 1. Introduction

The Intent Framework is a system for creating conditional trading intents. It enables users to create time-bound, conditional offers that can be executed by third parties (solvers) when specific conditions are met. The framework provides a generic system for creating tradeable intents with built-in expiry, witness validation, and owner revocation capabilities, enabling sophisticated trading mechanisms like limit orders and conditional swaps.

The system consists of two primary components:

- **Move Intent Framework**: A set of Move smart contracts that implement the core intent creation, management, and execution logic. The framework supports multiple intent types including unreserved intents (executable by any solver), reserved intents (pre-authorized solvers), and oracle-guarded intents (conditional on external data validation).

- **Trusted Verifier Service**: A Rust-based external service that monitors intent events on the hub chain, validates fulfillment conditions across connected chains, and provides cryptographic approvals for intent and escrow completion in cross-chain scenarios.

The framework can also function as an escrow mechanism, allowing funds to be locked and released based on verified conditions. This makes it suitable for applications requiring conditional payments, cross-chain trades, and other scenarios where execution depends on external state verification.

## 2. System Overview

The system follows a modular architecture with clear separation between on-chain smart contract logic and off-chain verification services.

### 2.1 Move Intent Framework

Deployed smart contracts handle intent lifecycle management, event emission for intent discovery, witness-based verification system for condition enforcement, and integration with native blockchain asset standards.

```text
move-intent-framework/sources/
├── intent.move                  # Core generic intent framework with abstract structures for conditional trades
├── fa_intent.move              # Concrete implementation for fungible asset limit orders
├── fa_intent_with_oracle.move # External data validation for conditional execution
├── intent_as_escrow.move       # Escrow abstraction layer for conditional payments
└── intent_reservation.move     # Solver authorization system for reserved intents
```

### 2.2 Trusted Verifier Service

Event monitoring service for intent and escrow events, cross-chain condition validation, cryptographic approval/rejection service, and REST API for signature retrieval.

```text
trusted-verifier/src/
├── monitor/              # Polls blockchain events for intent creation and escrow operations
├── validator/            # Validates fulfillment conditions across connected chains
├── crypto/               # Generates Ed25519 signatures for intent and escrow completion
└── api/                  # REST API exposing health checks, event queries, and signature endpoints
```

### 2.3 Intent Execution Flows

Intent execution follows a two-phase session model: `start_intent_session()` initiates fulfillment, and `finish_intent_session()` completes with witness verification. Execution may be restricted based on reservation status or require oracle attestation depending on intent configuration.

### 2.4 Cross-Chain Architecture

For cross-chain scenarios, the system operates with a hub-and-spoke model:

- **Hub Chain**: Hosts intent creation and final settlement
- **Connected Chains**: Host escrow deposits and conditional resource locking
- **Trusted Verifier**: Acts as a bridge service monitoring both hub and connected chains, validating cross-chain conditions, and providing cryptographic proofs

The verifier ensures that escrow operations on connected chains match the intent requirements on the hub chain before providing approval signatures.

### 2.5 Architectural Principles

The system is designed with the following principles:

- **Generic and Extensible**: Base intent module can be implemented for any conditional trade type
- **Type-Safe Verification**: Move's type system enforces witness creation only through proper verification paths
- **Event-Driven Discovery**: Intent availability is broadcast via events for external system integration
- **Security First**: Escrow operations require non-revocable intents; witness system prevents condition bypass
- **Modular Design**: Clear separation between generic framework and concrete implementations

## 3. Functional Requirements

## 4. Non-Functional Requirements

## 5. Security Requirements

## 6. Integration Requirements

## 7. Performance Requirements

## 8. Deployment Requirements

## 9. Testing Requirements

## 10. Operational Requirements

## 11. Constraints and Assumptions

## 12. Future Enhancements
