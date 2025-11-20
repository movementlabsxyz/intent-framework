# Domain Boundaries and Interfaces

This document provides precise definitions of domain boundaries, external interfaces, internal components, data ownership, and interaction protocols following RPG methodology principles.

## Intent Management: Boundaries and Interfaces

### Intent Management: Domain Boundaries

**In Scope**:

- Intent creation, lifecycle management, and validation
- Witness type system and verification
- Intent reservation mechanisms
- Event emission for external monitoring
- Cross-chain intent creation (zero-amount source intents)

**Out of Scope**:

- Asset custody (belongs to Escrow Domain)
- Verifier approval logic (belongs to Verification Domain)
- Escrow-specific operations (belongs to Escrow Domain)

### External Interfaces

**Public Entry Functions** (Move):

- `create_fa_to_fa_intent_entry()` - Create fungible asset intent
- `create_cross_chain_request_intent_entry()` - Create cross-chain request intent
- `fulfill_cross_chain_request_intent()` - Fulfill cross-chain intent
- `create_reserved_intent()` - Create reserved intent with solver signature

**Public Functions** (Move):

- `create_intent<Source, Args>()` - Generic intent creation
- `start_intent_session<Source, Args>()` - Start intent session
- `finish_intent_session<Witness, Args>()` - Complete intent session
- `revoke_intent()` - Revoke intent (if revocable)

**Events Emitted**:

- `LimitOrderEvent` - Intent creation event (fa_intent.move)
- `LimitOrderFulfillmentEvent` - Intent fulfillment event (fa_intent.move)
- `OracleLimitOrderEvent` - Oracle-guarded intent event (fa_intent_with_oracle.move)

**Data Structures Exported**:

- `TradeIntent<Source, Args>` - Core intent structure
- `TradeSession<Args>` - Active trading session
- `FungibleAssetLimitOrder` - FA trading conditions
- `OracleGuardedLimitOrder` - Oracle-guarded trading conditions
- `IntentReserved` - Solver reservation structure

### Intent Management: Internal Components

- Witness type system (`FungibleAssetRecipientWitness`, etc.)
- Intent expiry validation logic
- Reservation signature verification
- Event emission infrastructure

### Intent Management: Data Ownership

- **Intent Objects**: Owned by intent creator until fulfilled or revoked
- **Intent State**: Stored in Move object system, managed by Intent Management domain
- **Session State**: Hot potato types, must be consumed by completion

### Intent Management: Interaction Protocols

For comprehensive inter-domain interaction patterns, see [Inter-Domain Interaction Patterns and Dependencies](architecture-component-mapping.md#inter-domain-interaction-patterns-and-dependencies) in the architecture component mapping document.

---

## Escrow: Boundaries and Interfaces

### Escrow: Domain Boundaries

**In Scope**:

- Asset custody and fund locking on individual chains
- Escrow creation with verifier public key
- Escrow completion with verifier signature (signature itself is the approval)
- Reserved solver address enforcement
- Non-revocable requirement enforcement

**Out of Scope**:

- Intent creation logic (belongs to Intent Management Domain)
- Verifier monitoring and validation (belongs to Verification Domain)
- Cross-chain intent creation (belongs to Intent Management Domain)

### Escrow: External Interfaces

**Public Entry Functions** (Move):

- `create_escrow_from_fa()` - Create escrow from fungible asset
- `complete_escrow_from_fa()` - Complete escrow with verifier signature (signature itself is the approval)

**Public Functions** (Move):

- `create_escrow()` - Create escrow with verifier requirement
- `start_escrow_session()` - Start escrow session (solver takes escrowed assets)
- `complete_escrow()` - Complete escrow with verifier signature (signature itself is the approval)

**Public Functions** (Solidity):

- `createEscrow(uint256 intentId, address token, uint256 amount, address reservedSolver)` - Create and deposit escrow
- `deposit(uint256 intentId, address token, uint256 amount)` - Additional deposit to escrow
- `claim(uint256 intentId, bytes signature)` - Claim escrow with verifier signature (signature itself is the approval)
- `cancel(uint256 intentId)` - Cancel escrow after expiry

**Events Emitted**:

- `OracleLimitOrderEvent` - Escrow creation event (Move)
- `EscrowInitialized` - Escrow creation event (EVM)
- `DepositMade` - Additional deposit event (EVM)
- `EscrowClaimed` - Escrow claim event (EVM)
- `EscrowCancelled` - Escrow cancellation event (EVM)

**Data Structures Exported**:

- `EscrowConfig` - Escrow configuration (Move)
- `Escrow` struct - Escrow data structure (EVM)

### Escrow: Internal Components

- Non-revocable enforcement logic (`revocable = false` requirement)
- Reserved solver address validation
- Verifier signature verification (Ed25519 for Move, ECDSA for EVM)
- Expiry-based cancellation logic

### Escrow: Data Ownership

- **Escrowed Assets**: Locked in escrow contract/module until released or cancelled
- **Escrow State**: Owned by escrow contract, managed by Escrow domain
- **Reserved Solver**: Enforced at creation, cannot be changed

### Escrow: Interaction Protocols

For comprehensive inter-domain interaction patterns, see [Inter-Domain Interaction Patterns and Dependencies](architecture-component-mapping.md#inter-domain-interaction-patterns-and-dependencies) in the architecture component mapping document.

---

## Settlement: Boundaries and Interfaces

### Settlement: Domain Boundaries

**In Scope**:

- Intent fulfillment operations
- Escrow completion and claim operations
- Asset transfer coordination
- Expiry and cancellation handling

**Out of Scope**:

- Intent creation (belongs to Intent Management Domain)
- Escrow creation (belongs to Escrow Domain)
- Verifier validation (belongs to Verification Domain)

**Note**: Settlement functionality is distributed across Intent Management and Escrow modules, not a separate structural module.

### Settlement: External Interfaces

**Public Entry Functions** (Move):

- `fulfill_cross_chain_request_intent()` - Fulfill cross-chain intent (in fa_intent.move)
- `complete_escrow_from_fa()` - Complete escrow with verifier signature (in intent_as_escrow_entry.move) - signature itself is the approval

**Public Functions** (Move):

- `finish_fa_intent_session()` - Complete FA intent session (in fa_intent.move)
- `complete_escrow()` - Complete escrow with verifier signature (in intent_as_escrow.move) - signature itself is the approval

**Public Functions** (Solidity):

- `claim(uint256 intentId, bytes signature)` - Claim escrow (in IntentEscrow.sol) - signature itself is the approval
- `cancel(uint256 intentId)` - Cancel escrow after expiry (in IntentEscrow.sol)

### Settlement: Internal Components

- Fulfillment validation logic (witness verification, condition checking)
- Verifier signature verification
- Asset transfer execution
- Expiry validation

### Settlement: Data Ownership

- **Fulfilled Assets**: Transferred from intent creator to solver
- **Escrowed Assets**: Transferred from escrow to reserved solver
- **Session State**: Consumed during completion (hot potato pattern)

### Settlement: Interaction Protocols

For comprehensive inter-domain interaction patterns, see [Inter-Domain Interaction Patterns and Dependencies](architecture-component-mapping.md#inter-domain-interaction-patterns-and-dependencies) in the architecture component mapping document.

---

## Verification: Boundaries and Interfaces

### Verification: Domain Boundaries

**In Scope**:

- Event monitoring from hub and connected chains (Move VM and EVM)
- Symmetrical monitoring of Move VM and EVM escrows (both cached and validated when created)
- Cross-chain state validation
- Approval signature generation (Ed25519 for Move VM, ECDSA for EVM)
- Event correlation and matching
- REST API for external integration

**Out of Scope**:

- Intent creation (belongs to Intent Management Domain)
- Escrow creation (belongs to Escrow Domain)
- Asset custody (belongs to Escrow Domain)

### Verification: External Interfaces

**REST API Endpoints**:

- `GET /health` - Health check
- `GET /public-key` - Get verifier public key
- `GET /events` - Get cached events (intents, escrows, fulfillments)
- `GET /approvals` - Get cached approval signatures
- `GET /approvals/:escrow_id` - Get approval for specific escrow
- `POST /approval` - Manually create approval signature
- `POST /validate-outflow-fulfillment` - Validate connected chain transaction for outflow intent and return approval signature
- `POST /validate-inflow-escrow` - Validate escrow deposit for inflow intent

**Public Functions** (Rust):

- `EventMonitor::poll_hub_events()` - Poll hub chain for intent events
- `EventMonitor::poll_connected_events()` - Poll Move VM connected chain for escrow events
- `EventMonitor::poll_evm_events()` - Poll EVM connected chain for escrow events
- `EventMonitor::monitor_hub_chain()` - Monitor hub chain continuously
- `EventMonitor::monitor_connected_chain()` - Monitor Move VM connected chain continuously
- `EventMonitor::monitor_evm_chain()` - Monitor EVM connected chain continuously
- `EventMonitor::get_cached_events()` - Get cached events
- `CrossChainValidator::validate_intent_safety()` - Validate intent safety
- `CrossChainValidator::validate_fulfillment()` - Validate fulfillment
- `CrossChainValidator::validate_intent_fulfillment()` - Validate escrow fulfills intent
- `validator::inflow_evm::validate_evm_escrow_solver()` - Validate EVM escrow solver matches registry (standalone function in `validator/inflow_evm.rs`)
- `CryptoService::create_mvm_approval_signature(intent_id)` - Generate Ed25519 approval signature (Move VM) - signs the `intent_id`
- `CryptoService::create_evm_approval_signature(intent_id)` - Generate ECDSA approval signature (EVM) - signs the `intent_id`

**Data Structures Exported**:

- `RequestIntentEvent` - Normalized request intent event structure
- `EscrowEvent` - Normalized escrow event structure with `chain_type` field (Mvm, Evm, Svm) set by verifier based on monitor that discovered it
- `FulfillmentEvent` - Normalized fulfillment event structure
- `ApprovalSignature` - Approval signature structure
- `ValidationResult` - Validation result structure

### Verification: Internal Components

- Event polling and caching mechanisms (symmetrical for Move VM and EVM)
- Cross-chain event correlation logic (`intent_id` matching)
- Chain ID validation (ensures escrow created on correct connected chain)
- Solver address validation (Move VM addresses directly, EVM addresses via solver registry)
- Cryptographic operations (Ed25519 for Move VM, ECDSA for EVM)
- Configuration management
- Blockchain RPC clients (MvmClient for Move VM chains, EvmClient for EVM chains)

### Verification: Data Ownership

- **Event Cache**: Owned by Verification domain, populated from blockchain events
- **Approval Signatures**: Generated by Verification domain, cached for retrieval
- **Configuration**: Owned by Verification domain, loaded from config files

### Verification: Interaction Protocols

For comprehensive inter-domain interaction patterns, see [Inter-Domain Interaction Patterns and Dependencies](architecture-component-mapping.md#inter-domain-interaction-patterns-and-dependencies) in the architecture component mapping document.
