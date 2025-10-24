# Trusted Verifier Service

⚠️ **NOTE**: Initially this handles a very simple case - transfers from a connected chain to the hub!

A trusted verifier service that monitors escrow deposit events and triggers actions on other chains or systems.

## Overview

The trusted verifier is an external service that:

1. **Monitors intent events** on the hub chain for new intents
2. **Monitors escrow events** from escrow systems
3. **Validates fulfillment of intent** (deposit conditions) on the connected chain
4. **Provides approval/rejection confirmation for intent fulfillment**
5. **Provides approval/rejection for escrow completion**

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Chain 1         │    │ Trusted Verifier │    │ Chain 2         │
│ (Hub)           │    │                  │    │ (Connected)     │
│                 │    │                  │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │ Intent      │ │◄───┤ │ Event Monitor│ │    │ │ Escrow      │ │
│ │ Framework   │ │    │ │              │ │───►│ │             │ │
│ │             │ │    │ │ Cross-chain  │ │    │ │             │ │
│ │             │ │    │ │ Validator    │ │    │ │             │ │
│ └─────────────┘ │    │ └──────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Security Requirements

⚠️ **CRITICAL**: The verifier must ensure that escrow intents are **non-revocable** (`revocable = false`) before triggering any actions elsewhere.

## Components

- **Event Monitor**: Listens for escrow deposit events
- **Cross-chain Validator**: Validates conditions on connected chain
- **Action Trigger**: Triggers actions based on validation results (both on hub and connected chain)
- **Approval Service**: Provides approval/rejection signatures (both on hub and connected chain)

## Development

This service will be implemented as a separate service that can:
- Monitor blockchain events
- Validate conditions on connected chain
- Trigger actions on hub and connected chain
- Provide cryptographic signatures for approval

## Integration

The verifier integrates with escrow systems by:
1. Monitoring `LimitOrderEvent` and `OracleLimitOrderEvent`
2. Validating deposit conditions
3. Providing approval signatures for escrow completion
4. Ensuring non-revocable escrow intents
