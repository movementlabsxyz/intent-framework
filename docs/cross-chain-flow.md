# Cross-Chain Flow

The intent framework enables cross-chain escrow operations where intents are created on a hub chain and escrows are created on connected chains. The verifier monitors both chains and provides approval signatures to authorize escrow release.

```mermaid
sequenceDiagram
    participant Alice as Alice
    participant Bob as Bob
    participant Hub as Hub Chain
    participant Verifier as Verifier
    participant Connected as Connected Chain

    Alice->>Hub: create request intent
    Hub->>Verifier: (observe) LimitOrderEvent

    Alice->>Connected: create escrow (intent_id, verifier pk, reserved_solver)
    Connected->>Verifier: (observe) OracleLimitOrderEvent

    Bob->>Hub: fulfill intent
    Hub->>Verifier: (observe) FulfillmentEvent

    Verifier->>Bob: approval signature for escrow release
    Bob->>Connected: complete_escrow_from_fa(escrow_id, approval)
```

## Flow Steps

1. **Hub**: Alice creates regular (non-oracle) intent (emits `LimitOrderEvent`)
2. **Connected**: Alice creates escrow (non-revocable), includes verifier public key, links `intent_id`, and specifies reserved solver address (emits `OracleLimitOrderEvent`)
3. **Hub**: Bob fulfills the intent (emits `LimitOrderFulfillmentEvent`)
4. **Verifier**: observes fulfillment + escrow, generates approval signature (BCS(u64=1))
5. **Script**: submits `complete_escrow_from_fa` on connected chain with approval signature

**Note**: All escrows must specify a reserved solver address at creation. Funds are always transferred to the reserved solver when the escrow is claimed, regardless of who sends the transaction.

