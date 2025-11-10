# Requirements Document

> **Note**: This is a working document and may be deleted once sufficient progress has been made and the requirements are reflected in the implementation and other documentation.

## Document Scope

This document specifies **requirements** for the Intent Framework—what the system must support and how it should behave. It focuses on requirements not covered in the other taskmaster architecture documents:

- **[Section 2: Cross-Chain Architecture](#2-system-overview)** - Future cross-chain flow requirements (Inflow and Outflow) with sequence diagrams. These flows are not yet implemented; other taskmaster docs describe current implementation.

- **[Section 3: Functional Requirements](#3-functional-requirements)** - High-level functional capabilities the system must support.

- **[Section 4: Non-Functional Requirements](#4-non-functional-requirements)** - System-level quality attributes (reliability, availability, usability, compatibility) not covered by architecture docs.

- **[Section 5: Performance Requirements](#5-performance-requirements)** - (Empty)

- **[Section 6: Deployment Requirements](#6-deployment-requirements)** - (Empty)

- **[Section 7: Testing Requirements](#7-testing-requirements)** - Testing capabilities the system must support.

- **[Section 8: Constraints and Assumptions](#8-constraints-and-assumptions)** - (Empty)

- **[Section 9: Future Enhancements](#9-future-enhancements)** - (Empty)


## 1. Introduction

The Intent Framework is a system for creating conditional trading intents. It enables users to create time-bound, conditional offers that can be executed by third parties (solvers) when specific conditions are met. The framework provides a generic system for creating tradeable intents with built-in expiry, witness validation, and owner revocation capabilities, enabling sophisticated trading mechanisms like limit orders and conditional swaps.

The system consists of two primary components:

- **Move Intent Framework**: A set of Move smart contracts that implement the core intent creation, management, and execution logic. The framework supports multiple intent types including unreserved intents (executable by any solver), reserved intents (pre-authorized solvers), and oracle-guarded intents (conditional on external data validation).

- **Trusted Verifier Service**: A Rust-based external service that monitors intent events on the hub chain, validates fulfillment conditions across connected chains, and provides cryptographic approvals for intent and escrow completion in cross-chain scenarios.

The framework can also function as an escrow mechanism, allowing funds to be locked and released based on verified conditions. This makes it suitable for applications requiring conditional payments, cross-chain trades, and other scenarios where execution depends on external state verification.

## 2. System Overview

The system follows a modular architecture with clear separation between on-chain smart contract logic and off-chain verification services. For detailed component organization and domain boundaries, see [Component-to-Domain Mapping](architecture-component-mapping.md) and [Domain Boundaries and Interfaces](domain-boundaries-and-interfaces.md).

### 2.1 Cross-Chain Architecture

For cross-chain scenarios, the system operates with a hub-and-spoke model:

- **Hub Chain**: Hosts intent creation and final settlement
- **Connected Chains**: Host escrow deposits and conditional resource locking
- **Trusted Verifier**: Acts as a bridge service monitoring both hub and connected chains, validating cross-chain conditions, and providing cryptographic proofs

The verifier ensures that escrow operations on connected chains match the intent requirements on the hub chain before providing approval signatures.

#### Cross-Chain Flows

The cross-chain intent protocol supports two primary flows: **Inflow** (Connected Chain → Movement) and **Outflow** (Movement → Connected Chain). These flows enable smooth "deposit → instant credit" UX while maintaining system security through solver collateral and partial slashing mechanisms.

##### Inflow (Connected Chain → Movement)

This flow enables users to deposit tokens on a connected chain and receive equivalent tokens on Movement (hub chain).

```mermaid
sequenceDiagram
    participant User
    participant SolverNetwork as Solver Network
    participant Connected as Connected Chain<br/>(Solana/Base/Ethereum/Sui/Aptos)
    participant Verifier as Trusted Verifier
    participant Movement as Movement<br/>(Hub Chain)

    Note over User,Movement: Phase 1: Off-Chain Intent Request
    User->>SolverNetwork: Creates unreserved intent, broadcasts to solver network

    Note over User,Movement: Phase 2: Solver Offers
    SolverNetwork->>User: Solvers sign offers and return to user

    Note over User,Movement: Phase 3: User Selection & Deposit
    User->>User: Selects solver offer, signs it (for hub)
    alt Bypass Mode
        User->>Connected: Sends deposit tx with USDC in escrow
        User->>Movement: Commits intent selection directly
    else Verifier-Gated Mode
        User->>Verifier: Sends deposit tx + intent selection
        Verifier->>Connected: Commits escrow creation
        Verifier->>Movement: Commits intent selection
    end

    Note over User,Movement: Phase 4: Solver Detection & Credit
    SolverNetwork->>Connected: Detects deposit (directly or via trusted monitoring)
    SolverNetwork->>Movement: Transfers equivalent USDC.e to user's wallet

    Note over User,Movement: Phase 5: Solver Fulfillment
    SolverNetwork->>Movement: Submits fill_intent(intent_id, tx_hash)

    Note over User,Movement: Phase 6: Verifier Validation
    Verifier->>Verifier: Validates in real-time:<br/>- Confirms min_conf finality<br/>- Verifies token = USDC<br/>- Verifies destination & amount<br/>- Uses multi-RPC quorum (≥2 receipts)

    alt Valid
        Verifier->>Connected: Calls finalize(intent_id, solver)
        Connected->>SolverNetwork: Transfers escrowed USDC.e → solver (minus fee)
        Connected->>SolverNetwork: Releases solver's locked collateral
    else Invalid/Expired
        Note over Connected: Intent remains OPEN
        alt Solver claimed but didn't deliver
            Connected->>SolverNetwork: Slashes 0.5-1% of collateral
            Connected->>SolverNetwork: Unlocks remainder
        end
    end
```

**Flow Steps**:

1. **User off-chain intent request**: User creates unreserved intent and broadcasts to solver network

2. **Solvers sign offers**: Solvers respond with signed offers and return to user

3. **User signs offer**: User selects a solver offer, signs it (for hub), and sends deposit transaction with USDC in escrow for connected chain (e.g., Solana, Base, Ethereum, Sui, Aptos) to the verifier

   **Alternative Options**: User/relayer can commit this on-chain directly (bypass mode) or verifier can submit commit (verifier-gated mode)

4. **Verifier commits both actions on-chain**: Verifier commits the user's intent selection and escrow creation

5. **Solver detects the deposit**: Solver detects deposit (directly or via trusted monitoring), then transfers equivalent USDC.e to the user's wallet on Movement

6. **Solver submits fulfillment**: Solver submits `fill_intent(intent_id, tx_hash)` on Movement, referencing the user's original connected-chain transaction

7. **Verifier validates in real-time**:
   - Confirms minimum confirmation finality (e.g., finalized Solana / 3–12 blocks EVM)
   - Verifies token = USDC, destination == expected deposit address, and amount ≥ required
   - Uses multi-RPC quorum (≥2 matching receipts)

8. **If valid → finalize**: `finalize(intent_id, solver)` is called on-chain on connected chain:
   - Protocol transfers user's escrowed USDC.e → solver (minus protocol fee)
   - Solver's locked collateral for that claim is released (configurable, may be set to 0 for trusted permissioned solvers)

9. **If invalid or expired → intent remains OPEN**:
   - If solver claimed but didn't deliver before deadline, a small fraction (0.5–1%) of its locked collateral is slashed; the rest unlocks

This process creates a smooth "deposit → instant credit" UX for users while keeping system risk bounded through solver collateral and partial slashing.

##### Outflow (Movement → Connected Chain)

This flow enables users to withdraw tokens from Movement to a connected chain.

```mermaid
sequenceDiagram
    participant User
    participant SolverNetwork as Solver Network
    participant Movement as Movement<br/>(Hub Chain)
    participant Verifier as Trusted Verifier
    participant Connected as Connected Chain<br/>(Destination)

    Note over User,Connected: Phase 1: Off-Chain Intent Request
    User->>SolverNetwork: Creates unreserved intent, broadcasts to solvers

    Note over User,Connected: Phase 2: Solver Offers
    SolverNetwork->>User: Solvers sign offers and return to user

    Note over User,Connected: Phase 3: User Selection & Reserved Intent
    User->>User: Selects solver offer, signs it
    alt Bypass Mode
        User->>Movement: Creates reserved intent directly<br/>(locks USDC.e escrow)
    else Verifier-Gated Mode
        User->>Verifier: Sends intent selection + solver offer
        Verifier->>Movement: Commits reserved intent on-chain
    end
    Note right of Movement: Reserved intent parameters:<br/>(amount, dst_chain, dst_token=USDC,<br/>dst_addr, expiry, min_conf_dst,<br/>fee_cap, nonce, selected_quote_id,<br/>solver_offer_sig)

    Note over User,Connected: Phase 4: User Posts Intent
    User->>Movement: Posts intent to withdraw USDC.e<br/>(amount, dst_chain, dst_addr, expiry, min_conf)

    Note over User,Connected: Phase 5: Solver Claims Intent
    SolverNetwork->>Movement: Claims intent, locks collateral<br/>(lock_ratio ≈ 10-20%, configurable to 0)

    Note over User,Connected: Phase 6: Commit Anchoring
    alt Bypass Mode
        Note over Movement: Already committed in Phase 3
    else Verifier-Gated Mode
        Verifier->>Movement: Commits reserved intent on-chain
    end

    Note over User,Connected: Phase 7: Solver Sends USDC
    SolverNetwork->>Connected: Sends USDC to dst_addr
    SolverNetwork->>SolverNetwork: Obtains tx_hash

    Note over User,Connected: Phase 8: Solver Submits Fulfillment
    SolverNetwork->>Movement: Submits fill_intent(intent_id, dst_tx_hash[, block_no, receipt_or_proof])

    Note over User,Connected: Phase 9: Verifier Validation
    Verifier->>Verifier: Validates transaction
    alt Valid
        Verifier->>Movement: Finalizes and transfers user escrow → solver (minus fee)
        Note over Movement: Alternatively: solver fulfills reserved intent with verifier approval
    else Invalid/Expired
        Movement->>SolverNetwork: Triggers collateral penalty (0.5-1%)
        Movement->>SolverNetwork: Unlocks remainder automatically
    end
```

**Flow Steps**:

1. **User off-chain intent request**: User creates unreserved intent and broadcasts to solver network

2. **Solvers sign offers**: Solvers respond with signed offers and return to user

3. **User selects & signs offer**: User selects a solver offer, signs it, then creates a reserved intent on Movement (locks USDC.e escrow) with parameters: `(amount, dst_chain, dst_token=USDC, dst_addr, expiry, min_conf_dst, fee_cap, nonce, selected_quote_id, solver_offer_sig)`

   **Bypass option**: User/relayer can commit this on-chain directly (since solver offer is attached). If verifier-gated: verifier can submit this commit instead

4. **User posts intent**: User posts an intent on Movement to withdraw USDC.e to a connected chain `(amount, dst_chain, dst_addr, expiry, min_conf)`

5. **Solver claims intent**: Solver claims the intent, locking a portion of its long-term collateral (`lock_ratio ≈ 10–20%`). Note: initially solvers may be permissioned and trusted, requiring configuration to 0 collateral

6. **Commit anchoring** (one of):
   - **Bypass mode**: Already committed in Step 3 (nothing to do here)
   - **Verifier-gated mode**: Verifier commits the reserved intent on-chain (mirroring Inflow's "commit both actions")

7. **Solver sends USDC**: Solver sends USDC on destination chain to `dst_addr`, obtains `tx_hash`, and submits it to Movement

8. **Solver submits fulfillment**: Solver submits `fill_intent(intent_id, dst_tx_hash[, block_no, receipt_or_proof])` on Movement

9. **Verifier validates**: Verifier validates the transaction; if correct, finalizes and transfers user escrow → solver (minus fee). Alternatively, solver can fulfill the reserved intent with verifier approval

10. **Failed or expired claims**: Trigger a small collateral penalty (0.5–1%), with remainder unlocked automatically

### 2.2 Architectural Principles

For detailed architectural principles and design philosophy, see the [Architecture Documentation](README.md):

- **[RPG Methodology Principles](rpg-methodology.md)** - Design philosophy and domain-based organization principles
- **[Component-to-Domain Mapping](architecture-component-mapping.md)** - How components are organized into domains and inter-domain interaction patterns
- **[Domain Boundaries and Interfaces](domain-boundaries-and-interfaces.md)** - Precise domain boundary definitions and interface specifications

## 3. Functional Requirements

This section specifies functional capabilities that the system must support. For detailed interface specifications, data structures, and current implementation details, see [Domain Boundaries and Interfaces](domain-boundaries-and-interfaces.md), [Data Models Documentation](data-models.md), and [Use Cases and Scenarios Documentation](use-cases.md).

### 3.1 Intent Creation and Execution

The system must support creating and executing intents with the following capabilities:

- **Unreserved Intent Creation**: Create intents executable by any solver
- **Reserved Intent Creation**: Enable off-chain negotiation and solver signature verification (Ed25519) to authorize specific solvers
- **Oracle-Guarded Intent Creation**: Create intents with external data validation requirements and oracle signature verification
- **Escrow Intent Creation**: Create escrow intents for conditional payments with verifier approval requirements
- **Move On-Chain Intent Execution**: Support two-phase session model (`start_intent_session()`, `finish_intent_session()`) for intents fulfilled entirely on a single chain
- **Intent Revocation**: Support revoking intents by creator (if `revocable = true`)
- **Expiry Handling**: Automatically prevent execution of expired intents
- **Event Emission**: Emit events for intent discovery and cross-chain coordination

### 3.2 Cross-Chain Intent Execution

For cross-chain intent flows involving multiple chains and verifiers, see [Cross-Chain Flows](#cross-chain-flows) (Inflow and Outflow). The system must support:

- Solver fulfillment submission with cross-chain transaction references (`fill_intent(intent_id, tx_hash)`)
- Cross-chain transaction validation with multi-RPC quorum (≥2 matching receipts)
- Verifier finalization with collateral management and slashing mechanisms
- Instant credit model where solver provides tokens before verification completes

### 3.3 Trusted Verifier Service

The system must provide a verifier service with the following capabilities:

- **Event Monitoring**: Monitor blockchain events from hub and connected chains, cache and process events in real-time
- **Cross-Chain Validation**: Validate escrow deposits match intent requirements, verify intent ID matching, validate metadata and amounts
- **Approval/Rejection Service**: Generate Ed25519 signatures for approval/rejection decisions, expose via REST API
- **Security Validation**: Enforce non-revocable escrow requirement, validate cryptographic signatures
- **REST API**: Provide health check, event queries, approval signature creation, and public key retrieval endpoints

## 4. Non-Functional Requirements

### 4.1 Reliability & Availability

#### 4.1.1 Verifier Service Availability

- Verifier service must maintain high availability for cross-chain operations
- Support graceful shutdown and restart without data loss
- Implement event caching to prevent data loss during service downtime
- Provide health check endpoint (`GET /health`) for monitoring service status

#### 4.1.2 Event Monitoring Reliability

- Event monitoring must not miss intent or escrow events
- Support proper event discovery mechanisms (Aptos Indexer GraphQL API recommended for production)
- Implement polling intervals with configurable timeout settings
- Handle blockchain RPC failures with appropriate timeout and retry logic
- Cache processed events to enable recovery and prevent duplicate processing

#### 4.1.3 Blockchain Dependency Management

- System depends on blockchain network availability for intent operations
- Intent creation and execution require blockchain to be operational
- Escrow operations require both hub and connected chain availability
- System must handle blockchain network unavailability gracefully (fail-safe behavior)
- Intent expiry mechanism provides automatic cleanup even if verifier is unavailable

#### 4.1.4 Fault Tolerance

- Verifier service must handle validation timeouts (configurable, default 30 seconds)
- Support idempotent approval/rejection signature generation
- Handle network failures in cross-chain validation
- Provide mechanisms to recover from missed events (event replay capabilities)

#### 4.1.5 Data Persistence

- Verifier service must maintain state for last observed events across restarts
- Cache intent and escrow event data for validation and signature retrieval
- Support persistence of approval/rejection decisions

### 4.2 Usability

#### 4.2.1 API Design

- Provide clear, consistent REST API endpoints for verifier service
- Use standard HTTP status codes and error responses
- Support CORS configuration for web application integration
- Expose comprehensive event data via API (`GET /events`)
- Provide self-documenting API design with clear endpoint purposes

#### 4.2.2 Error Handling

- Return clear, descriptive error codes for all failure scenarios
- Move modules must provide specific error codes: `EINTENT_EXPIRED`, `EINVALID_SIGNATURE`, `EUNAUTHORIZED_SOLVER`, `EINVALID_AMOUNT`, `EINVALID_METADATA`, `ESIGNATURE_REQUIRED`, `EORACLE_VALUE_TOO_LOW`
- Error messages must clearly indicate the cause of failure
- Failed transactions must abort cleanly with appropriate error codes

#### 4.2.3 Developer Experience

- Provide comprehensive documentation for API usage
- Include code examples for common use cases
- Support development environment setup with clear prerequisites
- Provide configuration templates with helpful comments
- Enable easy testing and deployment workflows

#### 4.2.4 Configuration Management

- Support configuration via TOML files for verifier service
- Provide configuration templates with default values
- Enable configuration of chain endpoints, keys, timeouts, and API settings
- Support different configurations for different environments (development, production)
- Provide clear error messages when configuration is missing or invalid

#### 4.2.5 Integration Ease

- Move modules must integrate seamlessly with blockchain's native fungible asset standards
- Event-driven design enables easy external system integration
- Generic type system allows extending to new asset types without framework changes
- Support simple escrow abstraction for common use cases

### 4.3 Compatibility

#### 4.3.1 Blockchain Network Compatibility

- Support deployment on Move-based blockchain networks
- Framework must work with networks implementing primary fungible store standards
- Support cross-chain scenarios with different blockchain networks (hub-and-spoke model)

#### 4.3.2 Event Discovery Compatibility

- Support multiple event discovery mechanisms:
  - Aptos Indexer GraphQL API (recommended for production scalability)
  - EventHandle with global resource (alternative, though deprecated in Aptos)
  - Transaction/block scanning (not recommended, testing only)
- Must handle both module events and EventHandle patterns
- Support querying events across all accounts (not limited to known accounts)

#### 4.3.3 Cryptographic Standards

- Use Ed25519 signature algorithm for solver authorization and verifier approvals
- Support standard Ed25519 key formats (base64 encoding for configuration)
- Compatible with Move's native Ed25519 signature verification
- Support signature verification for oracle attestations

#### 4.3.4 Asset Standard Compatibility

- Integrate with blockchain's native fungible asset standard
- Support `Object<Metadata>` and `FungibleAsset` types from standard library
- Use primary fungible store system for asset management
- Compatible with existing asset issuance and transfer mechanisms

#### 4.3.5 Cross-Chain Protocol Compatibility

- Support intent linking across different chains via `intent_id` field
- Enable verifier service to connect to multiple blockchain networks simultaneously
- Support different RPC endpoint formats and chain identifiers
- Handle network-specific differences in API responses gracefully

## 5. Performance Requirements

## 6. Deployment Requirements

## 7. Testing Requirements

### 7.1 Unit Tests

#### 7.1.1 Verifier Service Unit Tests

- Unit tests for verifier service components (event monitoring, cross-chain validation, cryptographic signing)

#### 7.1.2 Move Intent Framework Unit Tests

- Unit tests for Move intent framework modules (intent creation, execution, revocation, expiry handling, witness validation)

### 7.2 End-to-End Tests

- End-to-end tests using Docker setup with two chains (hub chain and connected chain)
- Test complete intent flows including cross-chain escrow validation
- Verify verifier service integration with multiple blockchain networks

## 8. Constraints and Assumptions

## 9. Future Enhancements
