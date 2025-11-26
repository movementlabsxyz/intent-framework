# Architecture Documentation

This directory contains internal architectural guidance documents for the Intent Framework. These documents provide a comprehensive mental model of the system's architecture, domain organization, and design principles.

## Document Overview

### [Component-to-Domain Mapping](architecture-component-mapping.md)

Maps all source files to their respective domains and documents inter-domain interaction patterns. This is the primary reference for understanding how components are organized and how domains interact.

**Key Sections**:

- Domain Architecture Overview (visual diagram)
- Topological Order (build sequence)
- Domain Definitions
- Component Mapping
- Inter-Domain Interaction Patterns and Dependencies

### [Domain Boundaries and Interfaces](domain-boundaries-and-interfaces.md)

Provides precise definitions of domain boundaries, external interfaces, internal components, data ownership, and interaction protocols following RPG methodology principles.

**Key Sections**:

- Intent Management: Boundaries and Interfaces
- Escrow: Boundaries and Interfaces
- Settlement: Boundaries and Interfaces
- Verification: Boundaries and Interfaces

### [RPG Methodology Principles](rpg-methodology.md)

Explains the Repository Planning Graph (RPG) methodology principles and how they apply to the Intent Framework architecture. This document provides the theoretical foundation for the domain-based organization.

**Key Sections**:

- Dual-Semantics (Functional vs. Structural)
- Explicit Dependencies
- Topological Order
- Progressive Refinement

### [Data Models Documentation](data-models.md)

Comprehensive reference for all data structures used across the Intent Framework, including intent structs, escrow structs, event structures, and cross-chain data linking patterns.

**Key Sections**:

- Intent Management Domain (Move data structures)
- Event Structures (Move event emissions)
- Escrow Domain (Move and Solidity escrow structures)
- Verification Domain (Rust normalized event structures)
- Cross-Chain Data Linking patterns

### [Conception Documents](conception/)

Documentation describing the conceptual design of the Intent Framework, including flows, scenarios, error cases, and security properties.

**Key Documents**:

- [Conception Generic](conception/conception_generic.md) - Introduction, actors, flow types, generic protocol steps, security properties, error cases, and risks
- [Conception Inflow](conception/conception_inflow.md) - Inflow flow (Connected Chain → Hub): use cases, protocol, scenarios, and protocol steps
- [Conception Outflow](conception/conception_outflow.md) - Outflow flow (Hub → Connected Chain): use cases, protocol, scenarios, and protocol steps
- [Conception Router Flow](conception/conception_routerflow.md) - Router flow (Connected Chain → Connected Chain): use cases, protocol, scenarios, and protocol steps
- [Architecture Differences](conception/architecture-diff.md) - Implementation status, function signatures, and differences from conception
- [Requirements](conception/requirements.md) - Functional and non-functional requirements

## How to Use These Documents

1. **New to the codebase?** Start with [Component-to-Domain Mapping](architecture-component-mapping.md) to understand how components are organized into domains.
2. **Need precise interface definitions?** See [Domain Boundaries and Interfaces](domain-boundaries-and-interfaces.md) for detailed boundary specifications.
3. **Understanding the design philosophy?** Read [RPG Methodology Principles](rpg-methodology.md) to understand why the architecture is organized this way.
4. **Need data structure details?** See [Data Models Documentation](data-models.md) for field-by-field documentation of all data structures.
5. **Understanding system behavior?** See [Conception Documents](conception/) for flows, scenarios, and error cases.
6. **Planning implementation?** Use the Topological Order sections to understand build dependencies and implementation sequence.

## Related Documentation

- [Protocol Specification](../../docs/protocol.md#cross-chain-flow) - Cross-chain intent protocol implementation details
- [Move Intent Framework](../../docs/move-intent-framework/README.md) - Move contract implementation
- [EVM Intent Framework](../../docs/evm-intent-framework/README.md) - Solidity contract implementation
- [Trusted Verifier](../../docs/trusted-verifier/README.md) - Verifier service implementation

## Document Relationships

```text
RPG Methodology Principles
    ↓ (provides methodology)
Component-to-Domain Mapping
    ↓ (references detailed boundaries)
Domain Boundaries and Interfaces
    ↓ (references data structures)
Data Models Documentation
    ↓ (all reference)
Protocol Specification (public docs/)
```

All architecture documents cross-reference each other and link to public component documentation for implementation details.
