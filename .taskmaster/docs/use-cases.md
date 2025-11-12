# Use Cases and Scenarios Documentation

This document documents architectural patterns and implementation-specific behaviors in the Intent Framework, focusing on error cases, edge cases, and real-world usage patterns. For happy path flows, see [protocol.md](../../docs/protocol.md#cross-chain-flow) and [technical overview](../../docs/move-intent-framework/technical-overview.md#intent-flow).

Each scenario references actual source files, function names, error codes, and event emissions from the implementation.

## Error Cases

### Intent Expiry

Behavior when `TradeIntent` expires before fulfillment.

**Error Code**: `EINTENT_EXPIRED` (`intent.move:11`)

**Triggering Condition**: `timestamp::now_seconds() > intent.expiry_time`

**Affected Operations**:

- `start_intent_session()` (`intent.move:114`) - aborts if intent expired
- EVM escrow expiry: After expiry, `claim()` is blocked but `cancel()` is allowed (`IntentEscrow.sol:28`)

**Implementation**: Expiry check occurs before session start, preventing fulfillment of expired intents.

### Invalid Witness

Error when wrong witness type is provided during intent fulfillment.

**Error Code**: `EINVALID_WITNESS` (`intent.move:20`)

**Triggering Condition**: `type_info::type_of<Witness>() != intent.witness_type`

**Affected Operations**:

- `finish_intent_session()` (`intent.move:179`) - aborts if witness type mismatch

**Implementation**: Type-safe witness system ensures only correct witness types can complete intents.

### Unauthorized Access

Errors for unauthorized intent revocation attempts.

**Error Codes**:

- `ENOT_OWNER` (`intent.move:17`) - caller is not intent owner
- `ENOT_REVOCABLE` (`intent.move:23`) - intent is not revocable

**Triggering Conditions**:

- `ENOT_OWNER`: `object::owner(intent) != signer::address_of(issuer)` (`intent.move:201`)
- `ENOT_REVOCABLE`: `intent.revocable == false` (`intent.move:212`)

**Affected Operations**:

- `revoke_intent()` (`intent.move:195-212`) - aborts if unauthorized or non-revocable

**Implementation**: Dual checks ensure only owner can revoke, and only revocable intents can be revoked.

### Cross-Chain Failures

Verifier signature validation failures and escrow claim rejections.

**Failure Scenarios**:

1. **Invalid Verifier Signature**:
   - Move: `complete_escrow_from_fa()` verifies Ed25519 signature (`intent_as_escrow.move:140-150`)
   - EVM: `claim()` verifies ECDSA signature (`IntentEscrow.sol:92-102`)
   - Transaction aborts if signature verification fails

2. **Approval Value Mismatch**:
   - Verifier must provide approval value >= 1 (`intent_as_escrow.move:93`)
   - Lower values result in escrow rejection

3. **Escrow Already Claimed**:
   - EVM: `isClaimed` flag prevents double-claiming (`IntentEscrow.sol:26`)

**Implementation**: Cryptographic signature verification ensures only verifier-authorized releases succeed.

### Token Type Mismatches

Errors when provided tokens don't match intent requirements.

**Error Code**: `ENOT_DESIRED_TOKEN` (`fa_intent.move:15`, `fa_intent_with_oracle.move:25`)

**Triggering Condition**: `fungible_asset::asset_metadata(&received_asset) != desired_metadata`

**Affected Operations**:

- `finish_fa_receiving_session()` (`fa_intent.move:257-280`) - aborts if token type mismatch
- `finish_fa_receiving_session_with_oracle()` (`fa_intent_with_oracle.move:224-250`) - aborts if token type mismatch

**Implementation**: Metadata comparison ensures only desired token types are accepted.

## Edge Cases

### Non-Revocable Escrow Intents

Critical security requirement that escrow intents must be non-revocable.

**Requirement**: All escrow intents MUST have `revocable = false`

**Implementation**:

- Move escrow creation enforces `revocable=false` (`intent_as_escrow.move:109`)
- EVM escrows use contract-defined expiry instead of revocation
- Verifier validates `escrow.revocable == false` before approval (critical check)

**Rationale**: Escrow funds must remain locked until verifier approval or expiry. If escrows were revocable, users could withdraw funds after verifiers trigger actions elsewhere, breaking protocol security guarantees.

### Reserved Solver Enforcement

Funds always transfer to reserved solver regardless of transaction sender.

**Implementation**:

- Move: `complete_escrow_from_fa()` transfers to `reserved_solver` from `reservation` (`intent_as_escrow.move:140-150`)
- EVM: `claim()` transfers to `reservedSolver` from escrow struct (`IntentEscrow.sol:92-102`)
- Transaction sender is irrelevant - funds always go to reserved solver

**Rationale**: Prevents unauthorized fund recipients and signature replay attacks. Ensures funds go to the solver who committed resources on other chains.

### Zero-Amount Cross-Chain Swaps

Behavior when source tokens aren't locked on hub chain.

**Implementation** (`fa_intent_cross_chain.move:40-41`):

- `create_cross_chain_request_intent()` withdraws 0 tokens (`primary_fungible_store::withdraw(account, source_metadata, 0)`)
- Creates intent with `source_amount=0` in `LimitOrderEvent`
- Tokens are locked in escrow on connected chain instead

**Use Case**: Enables cross-chain swaps where assets are on different chains, with hub chain serving as coordination layer.

### Concurrent Intent Fulfillment

Race condition prevention mechanisms.

**Prevention Mechanisms**:

- Move: Intent object is consumed during `start_intent_session()` (`intent.move:114-125`), preventing concurrent fulfillment
- EVM: `isClaimed` flag prevents double-claiming (`IntentEscrow.sol:26`)
- Session-based pattern ensures single fulfillment per intent

**Implementation**: Intent object destruction and state flags prevent multiple solvers from fulfilling the same intent concurrently.

## Real-World Usage Patterns

### Cross-Chain USD Token Transfer

Transferring USD tokens from a connected chain to a hub chain using the intent framework.

**Use Case**: A user wants to transfer USD tokens from Chain 2 (connected chain) to Chain 1 (hub chain). The tokens are locked in an escrow on Chain 2, and a solver provides equivalent tokens on Chain 1. After the solver fulfills the intent on Chain 1, the verifier approves the escrow release on Chain 2, transferring the locked tokens to the solver.

**Flow**:

1. **Hub Chain - Intent Creation** (`testing-infra/e2e-tests-apt/submit-hub-intent.sh`):
   - User creates cross-chain request intent on hub chain using `create_cross_chain_request_intent_entry()`
   - Intent specifies desired USD token metadata and amount (e.g., 100M tokens)
   - Intent uses `source_amount=0` since tokens are locked on connected chain
   - Intent is **reserved** for a specific solver: solver must be registered in the solver registry, signs the intent off-chain, and the signature is verified on-chain using the solver's public key from the registry
   - The solver's public key is looked up from the on-chain solver registry (no need to pass it explicitly)

2. **Connected Chain - Escrow Creation** (`testing-infra/e2e-tests-apt/submit-escrow.sh`):
   - User locks USD tokens in escrow on connected chain using `create_escrow_from_fa()`
   - Escrow specifies reserved solver address (funds will go to this address when released)
   - Escrow links to hub intent via shared `intent_id`
   - Escrow is non-revocable (`revocable=false`)

3. **Hub Chain - Intent Fulfillment** (`testing-infra/e2e-tests-apt/fulfill-hub-intent.sh`):
   - Solver monitors hub chain events and sees the intent
   - Solver provides USD tokens on hub chain using `fulfill_cross_chain_request_intent()`
   - User receives tokens on hub chain

4. **Verifier - Validation and Approval** (`testing-infra/e2e-tests-apt/release-escrow.sh`):
   - Verifier monitors hub chain for request intent events and connected chain (Aptos or EVM) for escrow events
   - Verifier actively polls connected chains and caches escrows when created (symmetrical for both Aptos and EVM)
   - Verifier validates escrow is non-revocable (critical security check)
   - Verifier validates solver addresses match (Aptos addresses directly, EVM addresses via solver registry)
   - Verifier validates `chain_id` matches between intent `connected_chain_id` and escrow `chain_id`
   - Verifier generates approval signature after hub fulfillment is confirmed (Ed25519 for Aptos, ECDSA for EVM)

5. **Connected Chain - Escrow Release** (`testing-infra/e2e-tests-apt/release-escrow.sh`):
   - Anyone can call `complete_escrow_from_fa()` with verifier approval signature
   - Funds are transferred to the reserved solver address specified at escrow creation
   - Solver receives locked tokens on connected chain
