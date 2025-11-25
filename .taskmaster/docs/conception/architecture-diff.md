# Architecture Differences

**Note**: This document highlights the differences between the conception documents (conception_generic.md, conception_inflow.md, conception_outflow.md, conception_routerflow.md) and the current implementation. It describes what has been implemented, what differs from the conceptual design, and what is planned for the future.

## System Overview

The system follows a modular architecture with clear separation between on-chain smart contract logic and off-chain verification services. For detailed component organization and domain boundaries, see [Component-to-Domain Mapping](../architecture-component-mapping.md) and [Domain Boundaries and Interfaces](../domain-boundaries-and-interfaces.md).

### Cross-Chain Architecture

For cross-chain scenarios, the system operates with a hub-and-spoke model:

- **Hub Chain**: Hosts intent creation and final settlement
- **Connected Chains**: Host escrow deposits and conditional resource locking
- **Trusted Verifier**: Acts as a bridge service monitoring both hub and connected chains, validating cross-chain conditions, and providing cryptographic proofs

The verifier ensures that escrow operations on connected chains match the intent requirements on the hub chain before providing approval signatures.

#### Cross-Chain Flows

The cross-chain intent protocol supports three primary flows: **Inflow** (Connected Chain → Hub), **Outflow** (Hub → Connected Chain), and **Connected → Connected** (Connected Chain → Connected Chain). These flows enable smooth "deposit → instant credit" UX while maintaining system security through solver collateral and partial slashing mechanisms.

##### Inflow (Connected Chain → Movement)

This flow enables users to deposit offered tokens on a connected chain and receive desired tokens on Movement (hub chain).

```mermaid
sequenceDiagram
    participant Requester
    participant Hub as Hub Chain<br/>(Move)
    participant Verifier as Trusted Verifier<br/>(Rust)
    participant Connected as Connected Chain<br/>(Move/EVM)
    participant Solver

    Note over Requester,Solver: Phase 1: Intent Creation on Hub Chain
    Requester->>Requester: create_cross_chain_draft_intent()<br/>(off-chain, creates IntentDraft)
    Requester->>Solver: Send draft
    Solver->>Solver: Solver signs<br/>(off-chain, returns Ed25519 signature)
    Solver->>Requester: Returns signature
    Requester->>Hub: create_inflow_request_intent(<br/>offered_metadata, offered_amount, offered_chain_id,<br/>desired_metadata, desired_amount, desired_chain_id,<br/>expiry_time, intent_id, solver, solver_signature)
    Hub->>Verifier: LimitOrderEvent(intent_id, offered_amount,<br/>offered_chain_id, desired_amount,<br/>desired_chain_id, expiry, revocable=false)

    Note over Requester,Solver: Phase 2: Escrow Creation on Connected Chain
    alt Move Chain
        Requester->>Connected: create_escrow_from_fa(<br/>offered_metadata, amount, verifier_pk,<br/>expiry_time, intent_id, reserved_solver)
    else EVM Chain
        Requester->>Connected: createEscrow(intentId, token,<br/>amount, reservedSolver)
    end
    Connected->>Connected: Lock assets
    Connected->>Verifier: OracleLimitOrderEvent/EscrowInitialized(<br/>intent_id, reserved_solver, revocable=false)

    Note over Requester,Solver: Phase 3: Intent Fulfillment on Hub Chain
    Solver->>Hub: fulfill_inflow_request_intent(<br/>intent, payment_amount)
    Hub->>Verifier: LimitOrderFulfillmentEvent(<br/>intent_id, solver, provided_amount)

    Note over Requester,Solver: Phase 4: Verifier Validation and Approval
    Verifier->>Verifier: Validate fulfillment<br/>conditions met
    Verifier->>Verifier: Generate approval signature
    Note right of Verifier: [UNIMPLEMENTED] Multi-RPC quorum validation<br/>(≥2 matching receipts)

    Note over Requester,Solver: Phase 5: Escrow Release on Connected Chain
    Verifier->>Solver: Delivers approval signature<br/>(Ed25519 for Move, ECDSA for EVM)<br/>Signature itself is the approval
    alt Move Chain
        Note over Solver: Anyone can call<br/>(funds go to reserved_solver)
        Solver->>Connected: complete_escrow_from_fa(<br/>escrow_intent, payment_amount,<br/>verifier_signature_bytes)
    else EVM Chain
        Note over Solver: Anyone can call<br/>(funds go to reservedSolver)
        Solver->>Connected: claim(intentId, signature)
    end
    Connected->>Connected: Verify signature
    Connected->>Connected: Transfer to reserved_solver
    Note right of Connected: [UNIMPLEMENTED] Protocol fee deduction
    Note right of Connected: [UNIMPLEMENTED] Solver collateral release

    Note over Requester,Solver: [UNIMPLEMENTED] Phase 6: Collateral & Slashing
    Note right of Connected: [UNIMPLEMENTED] If validation fails or expired:<br/>- Slash 0.5-1% of solver collateral<br/>- Unlock remainder
```

**Implementation Details**: See [Inflow Flow Steps](../../docs/protocol.md#inflow-flow-steps) in `protocol.md` for the complete implemented flow.

**Future Enhancements (NOT YET IMPLEMENTED)**:

- **Multi-RPC Quorum**: Verifier uses multiple RPC endpoints with quorum validation (≥2 matching receipts) for enhanced security
- **Protocol Fees**: Automatic fee deduction from escrow transfers to solver
- **Solver Collateral**: Solvers lock collateral that can be slashed (0.5-1%) if validation fails or intent expires
- **Bypass/Verifier-Gated Modes**: Alternative flow modes where verifier commits transactions on behalf of users

##### Outflow (Movement → Connected Chain)

This flow enables users to lock offered tokens on Movement (hub chain) and receive desired tokens on a connected chain.

```mermaid
sequenceDiagram
    participant Requester
    participant Hub as Hub Chain<br/>(Move)
    participant Verifier as Trusted Verifier<br/>(Rust)
    participant Connected as Connected Chain<br/>(Move/EVM)
    participant Solver

    Note over Requester,Solver: Phase 1: Intent Creation on Hub Chain
    Requester->>Requester: create_cross_chain_draft_intent()<br/>(off-chain, creates IntentDraft)
    Requester->>Solver: Send draft
    Solver->>Solver: Solver signs<br/>(off-chain, returns Ed25519 signature)
    Solver->>Requester: Returns signature
    Requester->>Hub: create_outflow_request_intent(<br/>offered_metadata, offered_amount, offered_chain_id,<br/>desired_metadata, desired_amount, desired_chain_id,<br/>expiry_time, intent_id, requester_address_connected_chain,<br/>verifier_public_key, solver, solver_signature)
    Hub->>Hub: Lock assets on hub
    Hub->>Verifier: OracleLimitOrderEvent(intent_id, offered_amount,<br/>offered_chain_id, desired_amount,<br/>desired_chain_id, expiry, revocable=false)

    Note over Requester,Solver: [UNIMPLEMENTED] Phase 1.5: Solver Claims Intent
    Note right of Hub: [UNIMPLEMENTED] Solver claims intent and locks collateral<br/>(lock_ratio ≈ 10-20%, configurable to 0)

    Note over Requester,Solver: Phase 2: Solver Transfers on Connected Chain
    Solver->>Connected: Transfer tokens to requester_address_connected_chain<br/>(standard token transfer, not escrow)
    Connected->>Connected: Tokens received by requester

    Note over Requester,Solver: Phase 3: Verifier Validation and Approval
    Solver->>Verifier: POST /validate-outflow-fulfillment<br/>(transaction_hash, chain_type, intent_id)
    Verifier->>Connected: Query transaction by hash<br/>(verify transfer occurred)
    Verifier->>Verifier: Validate transfer conditions met
    Verifier->>Solver: Return approval signature

    Note over Requester,Solver: Phase 4: Intent Fulfillment on Hub Chain
    Solver->>Hub: fulfill_outflow_request_intent(<br/>intent, verifier_signature_bytes)
    Hub->>Hub: Verify verifier signature
    Hub->>Hub: Unlock tokens and transfer to solver
    Note right of Hub: [UNIMPLEMENTED] Protocol fee deduction

    Note over Requester,Solver: [UNIMPLEMENTED] Phase 5: Collateral & Slashing
    Note right of Hub: [UNIMPLEMENTED] If validation fails or expired:<br/>- Trigger collateral penalty (0.5-1%)<br/>- Unlock remainder automatically
```

**Implementation Details**: See [Outflow Flow Steps](../../docs/protocol.md#outflow-flow-steps) in `protocol.md` for the complete implemented flow.

**Future Enhancements (NOT YET IMPLEMENTED)**:

- **Solver Claims Intent**: Solver claims the intent, locking a portion of its long-term collateral (`lock_ratio ≈ 10-20%`, configurable to 0)
- **Protocol Fees**: Automatic fee deduction from hub token transfers to solver
- **Collateral Penalty**: If validation fails or intent expires, trigger collateral penalty (0.5-1%) and unlock remainder
- **Bypass/Verifier-Gated Modes**: Alternative flow modes where verifier commits transactions on behalf of users

##### Connected → Connected (Connected Chain → Connected Chain)

This flow enables users to transfer tokens from one connected chain to another connected chain, with tokens locked on the source connected chain and desired on the destination connected chain.

```mermaid
sequenceDiagram
    participant Requester
    participant Hub as Hub Chain<br/>(Move)
    participant Verifier as Trusted Verifier<br/>(Rust)
    participant Source as Source Connected Chain<br/>(Move/EVM)
    participant Dest as Destination Connected Chain<br/>(Move/EVM)
    participant Solver

    Note over Requester,Solver: Phase 1: Intent Creation on Hub Chain
    Requester->>Requester: create_cross_chain_draft_intent()<br/>(off-chain, creates IntentDraft)
    Requester->>Solver: Send draft
    Solver->>Solver: Solver signs<br/>(off-chain, returns Ed25519 signature)
    Solver->>Requester: Returns signature
    Requester->>Hub: create_cross_chain_request_intent(<br/>offered_metadata, offered_amount, offered_chain_id (source),<br/>desired_metadata, desired_amount, desired_chain_id (dest),<br/>expiry_time, intent_id, requester_address_dest_chain,<br/>verifier_public_key, solver, solver_signature)
    Hub->>Verifier: CrossChainOrderEvent(intent_id, offered_amount,<br/>offered_chain_id (source), desired_amount,<br/>desired_chain_id (dest), expiry, revocable=false)

    Note over Requester,Solver: Phase 2: Escrow Creation on Source Connected Chain
    alt Move Chain
        Requester->>Source: create_escrow_from_fa(<br/>offered_metadata, amount, verifier_pk,<br/>expiry_time, intent_id, reserved_solver)
    else EVM Chain
        Requester->>Source: createEscrow(intentId, token,<br/>amount, reservedSolver)
    end
    Source->>Source: Lock assets
    Source->>Verifier: OracleLimitOrderEvent/EscrowInitialized(<br/>intent_id, reserved_solver, revocable=false)

    Note over Requester,Solver: Phase 3: Solver Transfers on Destination Connected Chain
    Solver->>Dest: Transfer tokens to requester_address_dest_chain<br/>(standard token transfer, not escrow)
    Dest->>Dest: Tokens received by requester

    Note over Requester,Solver: Phase 4: Verifier Validation and Approval
    Solver->>Verifier: POST /validate-cross-chain-fulfillment<br/>(source_escrow_intent_id, dest_tx_hash, chain_types, intent_id)
    Verifier->>Source: Query escrow by intent_id<br/>(verify escrow exists and matches)
    Verifier->>Dest: Query transaction by hash<br/>(verify transfer occurred)
    Verifier->>Verifier: Validate fulfillment<br/>conditions met
    Verifier->>Solver: Return approval signature

    Note over Requester,Solver: Phase 5: Escrow Release on Source Connected Chain
    Verifier->>Solver: Delivers approval signature<br/>(Ed25519 for Move, ECDSA for EVM)<br/>Signature itself is the approval
    alt Move Chain
        Note over Solver: Anyone can call<br/>(funds go to reserved_solver)
        Solver->>Source: complete_escrow_from_fa(<br/>escrow_intent, payment_amount,<br/>verifier_signature_bytes)
    else EVM Chain
        Note over Solver: Anyone can call<br/>(funds go to reservedSolver)
        Solver->>Source: claim(intentId, signature)
    end
    Source->>Source: Verify signature
    Source->>Source: Transfer to reserved_solver
    Note right of Source: [UNIMPLEMENTED] Protocol fee deduction
    Note right of Source: [UNIMPLEMENTED] Solver collateral release

    Note over Requester,Solver: [UNIMPLEMENTED] Phase 6: Collateral & Slashing
    Note right of Source: [UNIMPLEMENTED] If validation fails or expired:<br/>- Slash 0.5-1% of solver collateral<br/>- Unlock remainder
```

**Implementation Details**: This flow combines elements of both inflow and outflow:

- **Hub request-intent**: Similar to both inflow and outflow, creates a cross-chain intent on the hub chain
- **Source connected chain escrow-intent**: Like inflow, tokens are locked in escrow on the source connected chain
- **Destination connected chain fulfill transaction**: Like outflow, solver transfers tokens directly on the destination connected chain

**Future Enhancements (NOT YET IMPLEMENTED)**:

- **Multi-RPC Quorum**: Verifier uses multiple RPC endpoints with quorum validation (≥2 matching receipts) for enhanced security
- **Protocol Fees**: Automatic fee deduction from escrow transfers to solver
- **Solver Collateral**: Solvers lock collateral that can be slashed (0.5-1%) if validation fails or intent expires
- **Bypass/Verifier-Gated Modes**: Alternative flow modes where verifier commits transactions on behalf of users

### Architectural Principles

For detailed architectural principles and design philosophy, see the [Architecture Documentation](../README.md):

- **[RPG Methodology Principles](../rpg-methodology.md)** - Design philosophy and domain-based organization principles
- **[Component-to-Domain Mapping](../architecture-component-mapping.md)** - How components are organized into domains and inter-domain interaction patterns
- **[Domain Boundaries and Interfaces](../domain-boundaries-and-interfaces.md)** - Precise domain boundary definitions and interface specifications
