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

This section specifies the functional capabilities and behaviors that the system must support, including the operations it must perform, the features it must provide, and how it must respond to user actions and system events.

### 3.1 Intent Creation

The system must support creating intents with the following capabilities:

#### 3.1.1 Unreserved Intent Creation

- Create intents that can be executed by any solver
- Lock offered resources on-chain with specified trading conditions
- Define expiry time (Unix timestamp) for automatic cleanup
- Configure revocability (whether creator can revoke before execution)
- Emit events upon intent creation for solver discovery

Relevant structures:

```move
struct TradeIntent<Source: store, Args: store + drop> has key {
    offered_resource: Source,
    argument: Args,
    expiry_time: u64,
    witness_type: TypeInfo,
    reservation: Option<IntentReserved>, // None for unreserved intents
    revocable: bool,
}

struct FungibleAssetLimitOrder has store, drop {
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    issuer: address,
    intent_id: Option<address>,
}
```

#### 3.1.2 Reserved Intent Creation

- Enable off-chain negotiation between intent creator and specific solver
- Support solver signature verification (Ed25519) to authorize specific solver
- Create intent reservations that restrict execution to authorized solvers
- Validate solver signatures before accepting reserved intents
- Ensure only authorized solver can execute reserved intents

Relevant structures:

`TradeIntent` from 3.1.1 with `reservation: Some(IntentReserved)`

```move
struct IntentReserved has store, drop {
    solver: address,
}

struct IntentDraft has copy, drop {
    source_metadata: Object<Metadata>,
    source_amount: u64,
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    expiry_time: u64,
    issuer: address,
}

struct IntentToSign has copy, drop {
    source_metadata: Object<Metadata>,
    source_amount: u64,
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    expiry_time: u64,
    issuer: address,
    solver: address,
}
```

#### 3.1.3 Oracle-Guarded Intent Creation

- Create intents with external data validation requirements
- Specify minimum threshold values for oracle-reported data
- Authorize specific oracle public keys for signature validation
- Require oracle signature witness during execution to verify external conditions
- Support conditional execution based on oracle data (e.g., price feeds)

Relevant structures:

`TradeIntent` from 3.1.1 with `argument: OracleGuardedLimitOrder`

```move
struct OracleGuardedLimitOrder has store, drop {
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    issuer: address,
    requirement: OracleSignatureRequirement,
}

struct OracleSignatureRequirement has store, drop, copy {
    min_reported_value: u64,
    public_key: ed25519::UnvalidatedPublicKey,
}

struct OracleSignatureWitness has drop {
    reported_value: u64,
    signature: ed25519::Signature,
}
```

#### 3.1.4 Escrow Intent Creation

- Create escrow intents for conditional payments
- Lock tokens awaiting verifier approval/rejection
- Specify verifier public key for authorization
- Require escrow intents to be non-revocable (`revocable = false`)
- Support linking escrow to intent IDs for cross-chain matching

Relevant structures:

`TradeIntent` from 3.1.1 with `argument: OracleGuardedLimitOrder` and `revocable: false`

```move
struct EscrowConfig has store, drop {
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    oracle_public_key: ed25519::UnvalidatedPublicKey, // Verifier public key
    expiry_time: u64,
}
```

### 3.2 Intent Execution

The system must support executing intents through a two-phase session model (session initiation and completion), with validation checks applied throughout the execution process:

#### 3.2.1 Session Initiation

- Provide `start_intent_session()` to begin intent fulfillment
- Verify intent has not expired before allowing session start
- Unlock offered resources and transfer to session opener
- Create `TradeSession` object containing trading conditions
- Check reservation requirements (if reserved intent, verify solver authorization)
- Return session object that must be completed or revoked

#### 3.2.2 Session Completion

- Provide `finish_intent_session()` to complete intent fulfillment
- Require appropriate witness proving trading conditions were met
- Verify witness type matches intent requirements at compile-time
- Transfer locked resources to solver upon successful completion
- Validate oracle signatures if intent is oracle-guarded
- Emit fulfillment events upon successful completion

#### 3.2.3 Execution Validation

- Verify expiry time has not been exceeded
- Validate solver authorization for reserved intents
- Check oracle signature and reported values meet thresholds
- Ensure correct witness type is provided
- Validate asset amounts and types match intent requirements

### 3.3 Further Intent Management Features

#### 3.3.1 Intent Revocation

- Support revoking intents by creator (if `revocable = true`)
- Return locked resources to original creator upon revocation
- Prevent revocation of non-revocable intents (especially escrow intents)
- Validate ownership before allowing revocation
- Clean up intent objects after revocation

#### 3.3.2 Expiry Handling

- Automatically prevent execution of expired intents
- Check expiry time during session start and completion
- Return error code `EINTENT_EXPIRED` when intent has expired
- Support cleanup of expired intent objects (via expiry time validation)

#### 3.3.3 Intent State Tracking

- Track intent creation, execution, and completion states
- Maintain immutable records of intent parameters
- Support querying intent status and parameters
- Track reservation status for reserved intents

### 3.4 Event Emission

#### 3.4.1 Intent Creation Events

- Emit `LimitOrderEvent` when fungible asset intents are created
- Include intent ID, source/desired asset metadata, amounts, expiry time, offerer, and solver (if reserved)
- Emit `OracleLimitOrderEvent` for oracle-guarded intents with oracle requirements
- Emit `OracleLimitOrderEvent` for escrow intents (escrow uses oracle-guarded intent system internally)
- Include oracle/verifier public key and minimum reported value in oracle events
- Make events discoverable by external systems and solvers

Event structures:

```move
struct LimitOrderEvent has store, drop {
    intent_address: address,
    intent_id: address,
    source_metadata: Object<Metadata>,
    source_amount: u64,
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    issuer: address,
    expiry_time: u64,
    revocable: bool,
}

struct OracleLimitOrderEvent has store, drop {
    intent_address: address,
    intent_id: address,
    source_metadata: Object<Metadata>,
    source_amount: u64,
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    issuer: address,
    expiry_time: u64,
    min_reported_value: u64,
    revocable: bool,
}
```

#### 3.4.2 Fulfillment Events

- Emit events when intents are successfully fulfilled
- Include intent ID, solver address, and fulfillment details
- Support event monitoring by verifier services for cross-chain coordination

Event structure:

```move
struct LimitOrderFulfillmentEvent has store, drop {
    intent_address: address,
    intent_id: address,
    solver: address,
    provided_metadata: Object<Metadata>,
    provided_amount: u64,
    timestamp: u64,
}
```

### 3.5 Trusted Verifier Service

#### 3.5.1 Event Monitoring

- Monitor blockchain events from hub and connected chains
- Poll or subscribe to intent creation events (`LimitOrderEvent`, `OracleLimitOrderEvent`)
- Poll or subscribe to escrow deposit events on connected chains
- Poll or subscribe to fulfillment events on hub chain
- Cache and process events in real-time

#### 3.5.2 Cross-Chain Validation

- Validate that escrow deposits on connected chains match intent requirements on hub chain
- Verify intent ID matching between hub intent and connected escrow
- Check that source amounts in escrow meet or exceed desired amounts in hub intent
- Validate metadata matches between intent and escrow
- Ensure expiry times are consistent
- Verify escrow intents are non-revocable before any cross-chain actions

#### 3.5.3 Approval/Rejection Service

- Generate Ed25519 signatures for approval/rejection decisions
- Provide approval signatures when hub intent is fulfilled and escrow conditions match
- Provide rejection signatures when conditions are not met
- Expose approval signatures via REST API endpoint
- Support retrieval of verifier public key for signature verification

#### 3.5.4 Security Validation

- Enforce that escrow intents have `revocable = false` before approval
- Reject any escrow intent that allows user revocation
- Validate cryptographic signatures (Ed25519) for solver authorization
- Verify oracle signatures when required

#### 3.5.5 REST API

- Provide health check endpoint (`GET /health`)
- Expose cached event data (`GET /events`)
- Allow approval signature creation (`POST /approval`)
- Expose verifier public key (`GET /public-key`)

### 3.6 Escrow Operations

#### 3.6.1 Escrow Creation

- Create escrow intents that lock tokens awaiting verifier approval
- Specify authorized verifier public key
- Set expiry time for automatic cleanup
- Require escrow intents to be non-revocable

#### 3.6.2 Escrow Session Management

- Support starting escrow session to take escrowed assets
- Enable verifier to approve or reject escrow release
- Require verifier signature for escrow completion
- Support revocation of escrow if rejected or expired

#### 3.6.3 Verifier Approval/Rejection

- Generate Ed25519 signatures for approval (value = 1) or rejection (value = 0)
- Verify verifier signatures match authorized public key
- Release escrowed assets only upon approval
- Return assets to creator upon rejection or expiry

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
