# Requirements

**Note**: This document highlights the differences between the conception documents (conception_generic.md, conception_inflow.md, conception_outflow.md, conception_routerflow.md) and the current implementation. It describes what has been implemented, what differs from the conceptual design, and what is planned for the future.

## Document Scope

This document specifies **requirements** for the Intent Framework—what the system must support and how it should behave. It focuses on requirements not covered in the other taskmaster architecture documents:

- **[Section 2: Functional Requirements](#2-functional-requirements)** - High-level functional capabilities the system must support.

- **[Section 3: Non-Functional Requirements](#3-non-functional-requirements)** - System-level quality attributes (reliability, availability, usability, compatibility) not covered by architecture docs.

- **[Section 4: Performance Requirements](#4-performance-requirements)** - (Empty)

- **[Section 5: Deployment Requirements](#5-deployment-requirements)** - (Empty)

- **[Section 6: Testing Requirements](#6-testing-requirements)** - Testing capabilities the system must support.

- **[Section 7: Constraints and Assumptions](#7-constraints-and-assumptions)** - (Empty)

- **[Section 8: Future Enhancements](#8-future-enhancements)** - (Empty)

## 2. Functional Requirements

This section specifies functional capabilities that the system must support. For detailed interface specifications, data structures, and current implementation details, see [Domain Boundaries and Interfaces](domain-boundaries-and-interfaces.md), [Data Models Documentation](data-models.md), and [Use Cases and Scenarios Documentation](use-cases.md).

### 2.1 Intent Creation and Execution

The system must support creating and executing intents with the following capabilities:

- **Unreserved Intent Creation**: Create intents executable by any solver
- **Reserved Intent Creation**: Enable off-chain negotiation and solver signature verification (Ed25519) to authorize specific solvers
- **Oracle-Guarded Intent Creation**: Create intents with external data validation requirements and oracle signature verification
- **Escrow Intent Creation**: Create escrow intents for conditional payments with verifier approval requirements
- **Move On-Chain Intent Execution**: Support two-phase session model (`start_intent_session()`, `finish_intent_session()`) for intents fulfilled entirely on a single chain
- **Intent Revocation**: Support revoking intents by creator (if `revocable = true`)
- **Expiry Handling**: Automatically prevent execution of expired intents
- **Event Emission**: Emit events for intent discovery and cross-chain coordination

### 2.2 Cross-Chain Intent Execution

For cross-chain intent flows involving multiple chains and verifiers, see [architecture-diff.md](architecture-diff.md). The system must support:

- Solver fulfillment submission with cross-chain transaction references (`fill_intent(intent_id, tx_hash)`)
- Cross-chain transaction validation with multi-RPC quorum (≥2 matching receipts)
- Verifier finalization with collateral management and slashing mechanisms
- Instant credit model where solver provides tokens before verification completes

### 2.3 Trusted Verifier Service

The system must provide a verifier service with the following capabilities:

- **Event Monitoring**: Monitor blockchain events from hub and connected chains, cache and process events in real-time
- **Cross-Chain Validation**: Validate escrow deposits match intent requirements, verify intent ID matching, validate metadata and amounts
- **Approval/Rejection Service**: Generate Ed25519 signatures for approval/rejection decisions, expose via REST API
- **Security Validation**: Enforce non-revocable escrow requirement, validate cryptographic signatures
- **REST API**: Provide health check, event queries, approval signature creation, and public key retrieval endpoints

## 3. Non-Functional Requirements

### 3.1 Reliability & Availability

#### 3.1.1 Verifier Service Availability

- Verifier service must maintain high availability for cross-chain operations
- Support graceful shutdown and restart without data loss
- Implement event caching to prevent data loss during service downtime
- Provide health check endpoint (`GET /health`) for monitoring service status

#### 3.1.2 Event Monitoring Reliability

- Event monitoring must not miss intent or escrow events
- Support proper event discovery mechanisms (Aptos Indexer GraphQL API recommended for production)
- Implement polling intervals with configurable timeout settings
- Handle blockchain RPC failures with appropriate timeout and retry logic
- Cache processed events to enable recovery and prevent duplicate processing

#### 3.1.3 Blockchain Dependency Management

- System depends on blockchain network availability for intent operations
- Intent creation and execution require blockchain to be operational
- Escrow operations require both hub and connected chain availability
- System must handle blockchain network unavailability gracefully (fail-safe behavior)
- Intent expiry mechanism provides automatic cleanup even if verifier is unavailable

#### 3.1.4 Fault Tolerance

- Verifier service must handle validation timeouts (configurable, default 30 seconds)
- Support idempotent approval/rejection signature generation
- Handle network failures in cross-chain validation
- Provide mechanisms to recover from missed events (event replay capabilities)

#### 3.1.5 Data Persistence

- Verifier service must maintain state for last observed events across restarts
- Cache intent and escrow event data for validation and signature retrieval
- Support persistence of approval/rejection decisions

### 3.2 Usability

#### 3.2.1 API Design

- Provide clear, consistent REST API endpoints for verifier service
- Use standard HTTP status codes and error responses
- Support CORS configuration for web application integration
- Expose comprehensive event data via API (`GET /events`)
- Provide self-documenting API design with clear endpoint purposes

#### 3.2.2 Error Handling

- Return clear, descriptive error codes for all failure scenarios
- Move modules must provide specific error codes: `EINTENT_EXPIRED`, `EINVALID_SIGNATURE`, `EUNAUTHORIZED_SOLVER`, `EINVALID_AMOUNT`, `EINVALID_METADATA`, `ESIGNATURE_REQUIRED`, `EORACLE_VALUE_TOO_LOW`
- Error messages must clearly indicate the cause of failure
- Failed transactions must abort cleanly with appropriate error codes

#### 3.2.3 Developer Experience

- Provide comprehensive documentation for API usage
- Include code examples for common use cases
- Support development environment setup with clear prerequisites
- Provide configuration templates with helpful comments
- Enable easy testing and deployment workflows

#### 3.2.4 Configuration Management

- Support configuration via TOML files for verifier service
- Provide configuration templates with default values
- Enable configuration of chain endpoints, keys, timeouts, and API settings
- Support different configurations for different environments (development, production)
- Provide clear error messages when configuration is missing or invalid

#### 3.2.5 Integration Ease

- Move modules must integrate seamlessly with blockchain's native fungible asset standards
- Event-driven design enables easy external system integration
- Generic type system allows extending to new asset types without framework changes
- Support simple escrow abstraction for common use cases

### 3.3 Compatibility

#### 3.3.1 Blockchain Network Compatibility

- Support deployment on Move-based blockchain networks
- Framework must work with networks implementing primary fungible store standards
- Support cross-chain scenarios with different blockchain networks (hub-and-spoke model)

#### 3.3.2 Event Discovery Compatibility

- Support multiple event discovery mechanisms:
  - Aptos Indexer GraphQL API (recommended for production scalability)
  - EventHandle with global resource (alternative, though deprecated in Aptos)
  - Transaction/block scanning (not recommended, testing only)
- Must handle both module events and EventHandle patterns
- Support querying events across all accounts (not limited to known accounts)

#### 3.3.3 Cryptographic Standards

- Use Ed25519 signature algorithm for solver authorization and verifier approvals
- Support standard Ed25519 key formats (base64 encoding for configuration)
- Compatible with Move's native Ed25519 signature verification
- Support signature verification for oracle attestations

#### 3.3.4 Asset Standard Compatibility

- Integrate with blockchain's native fungible asset standard
- Support `Object<Metadata>` and `FungibleAsset` types from standard library
- Use primary fungible store system for asset management
- Compatible with existing asset issuance and transfer mechanisms

#### 3.3.5 Cross-Chain Protocol Compatibility

- Support intent linking across different chains via `intent_id` field
- Enable verifier service to connect to multiple blockchain networks simultaneously
- Support different RPC endpoint formats and chain identifiers
- Handle network-specific differences in API responses gracefully

## 4. Performance Requirements

## 5. Deployment Requirements

## 6. Testing Requirements

### 6.1 Unit Tests

#### 6.1.1 Verifier Service Unit Tests

- Unit tests for verifier service components (event monitoring, cross-chain validation, cryptographic signing)

#### 6.1.2 Move Intent Framework Unit Tests

- Unit tests for Move intent framework modules (intent creation, execution, revocation, expiry handling, witness validation)

### 6.2 End-to-End Tests

- End-to-end tests using Docker setup with two chains (hub chain and connected chain)
- Test complete intent flows including cross-chain escrow validation
- Verify verifier service integration with multiple blockchain networks

## 7. Constraints and Assumptions

## 8. Future Enhancements
