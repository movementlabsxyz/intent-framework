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

## How to Use These Documents

1. **New to the codebase?** Start with [Component-to-Domain Mapping](architecture-component-mapping.md) to understand how components are organized into domains.

2. **Need precise interface definitions?** See [Domain Boundaries and Interfaces](domain-boundaries-and-interfaces.md) for detailed boundary specifications.

3. **Understanding the design philosophy?** Read [RPG Methodology Principles](rpg-methodology.md) to understand why the architecture is organized this way.

4. **Planning implementation?** Use the Topological Order sections to understand build dependencies and implementation sequence.

## Related Documentation

- [Protocol Specification](../../docs/protocol.md#cross-chain-flow) - Cross-chain intent protocol implementation details
- [Move Intent Framework](../../docs/move-intent-framework/README.md) - Move contract implementation
- [EVM Intent Framework](../../docs/evm-intent-framework/README.md) - Solidity contract implementation
- [Trusted Verifier](../../docs/trusted-verifier/README.md) - Verifier service implementation

## Document Relationships

```
RPG Methodology Principles
    ↓ (provides methodology)
Component-to-Domain Mapping
    ↓ (references detailed boundaries)
Domain Boundaries and Interfaces
    ↓ (all reference)
Protocol Specification (public docs/)
```

All three architecture documents cross-reference each other and link to public component documentation for implementation details.

