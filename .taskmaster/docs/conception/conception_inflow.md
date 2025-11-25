# Conception - Inflow Flow

This document describes the Inflow flow (Connected Chain → Hub). For general concepts, actors, and terminology, see [conception_generic.md](conception_generic.md).

## Use cases

For general use cases applicable to all flows, see [conception_generic.md](conception_generic.md). This section focuses on inflow-specific use cases.

### Users (Requester)

- As a requester, I want to swap some USDC from a connected chain to M1 chain so that I get my USDC on M1 chain fast and with low fee.

## Protocol

```mermaid
sequenceDiagram
    participant Requester
    participant Hub as Hub Chain
    participant Verifier
    participant Connected as Connected Chain
    participant Solver

    Note over Requester,Solver: Phase 1: Off-chain negotiation
    Requester->>Requester: Create draft intent
    Requester->>Solver: Send draft
    Solver->>Solver: Solver signs (off-chain)
    Solver->>Requester: Returns signature

    Note over Requester,Solver: Phase 2: Intent creation on Hub
    Requester->>Hub: Create reserved intent
    Hub->>Verifier: Intent event

    Note over Requester,Solver: Phase 3: Escrow on Connected Chain
    Requester->>Connected: Create escrow (locks tokens)
    Connected->>Verifier: Escrow event

    Note over Requester,Solver: Phase 4: Solver fulfillment
    Solver->>Hub: Fulfill intent
    Hub->>Verifier: Fulfillment event

    Note over Requester,Solver: Phase 5: Verifier validation and approval
    Verifier->>Verifier: Validate fulfillment conditions
    Verifier->>Solver: Generate approval signature

    Note over Requester,Solver: Phase 6: Escrow release
    Solver->>Connected: Release escrow (with verifier signature)
    Connected->>Connected: Transfer to reserved solver
```

## Scenarios

### Requester makes an inflow swap intent

0. Given the requester
   - owns the USDC that they want to transfer
   - owns some MOVE to execute Tx on M1 chain
   - owns offered tokens on connected chain
   - can access the connected chain and M1 chain RPC

1. When the requester wants to realize a swap from connected chain to M1 chain
   - then the requester requests a signed quote from a solver for the desired intent
   - then the requester sends a request-intent Tx to the M1 chain. ( 2) Requester initiates intent protocol step)
   - then the requester sends a Tx to connected chain to transfer the needed USDC + total fees token to an escrow. ( 1) Requester deposit protocol step)
   - then the requester waits for a confirmation of the swap
   - then the requester has received the requested amount of USDC in their M1 chain account.

#### Possible issues (Requester)

1. The requester initial escrow transfer is too little or too much.
    - Mitigation: The verifier verifies that the escrow transfer amount is the same as the request-intent offered amount.
1. The requester didn't get the right expected amount of USDC.
    - Mitigation: The verifier verifies that the escrow transfer amount is the same as the request-intent amount.

#### Questions

- Are the fees in USDC or in the chain token?

### Solver resolves an inflow swap intent

0. Given the solver
   - is registered in the solver registry on Hub chain
   - owns some MOVE to execute Tx on M1 chain
   - owns enough USDC on M1 chain
   - can access both chains' RPC
1. When the requester creates a draft intent and sends it to the solver
   - Then the solver signs the draft intent off-chain and returns signature
2. When the requester creates the reserved request-intent on Hub chain
   - Then the solver observes the request-intent and escrow events
   - Then the solver fulfills the request-intent on Hub chain (transfers desired tokens to requester)
   - Then the solver waits for verifier validation and approval
   - Then the solver claims the escrow funds on the connected chain

#### Possible issues (Solver)

- The solver doesn't send the right amount of desired tokens to the requester on Hub chain.
  - Mitigation: The solver submits the amount to the request-intent. The intent reverts if the amount is not the same as the request-intent requested amount.
- The solver doesn't receive the correct amount from escrow on connected chain.
  - Mitigation: The solver verifies that the escrow transfer amount is the same as the request-intent offered amount.
  - Mitigation: The verifier verifies that the escrow offered amount is the same as the request-intent offered amount and informs the solver.
- The solver is not notified of new intent request events.
  - Mitigation: The verifier receives intent-requests from the requester and forwards it to the pool of solvers.
- The solver attempts to fulfill an intent that wasn't reserved for them (on-chain verification prevents this).
  - Mitigation: The contract rejects the fulfillment if the intent is not reserved for the solver.

### The requeserter is adverse

0. Given the adversary takes the requester role to do a swap
1. When the adversary wants to extract more funds than the adversary has provided
   - Then the adversary sends a request-intent Tx to the M1 chain.
   - Then the adversary sends a Tx to the connected chain that transfers too little USDC token to an escrow.
   - Then the adversary hopes to get more USDC on the M1 chain than they have provided.
      - Mitigation: The solver verifies that the correct offered amount (USDC requested amount + fee) has been transferred to the escrow.
      - Mitigation: The verifier verifies that the escrow transfer amount is the same as the request-intent offered amount.
2. When the adversary attempts to stall the request-intent holding solver funds hostage.
   - Then the adversary reserves the intent
   - Then the adversary takes no action
      - Mitigation: The request-intent is protected by a timeout mechanism. After timeout, the intent is cancelled and the solver has no obligation to fulfill the intent any longer.

### The solver is adverse

0. Given the adversary takes the solver role to resolve an intent
1. When the adversary attempts to transfer less then the desired amount
   - Then the adversary reserves the intent
   - (Optional) Then the adversary transfers less funds than expected to the requester account.
   - Then the adversary hopes that the intent is fulfilled and the offered amount is transferred to the adversary account on the connected chain.
      - Mitigation: The smart contract rejects the fulfillment if the amount is less than the request-intent requested amount.
2. When the adversary attemtps to stall the request-intent.
   - Then the adversary reserves the intent
   - Then the adversary takes no action
      - Mitigation: The request-intent and the escrow is protected by a timeout mechanism. After timeout, the intent and escrow are cancelled and the funds are returned to the requester.

## Protocol steps details

**TODO : TO BE UPDATED**: This describes the Inflow flow (Connected Chain → Hub). The current implementation uses reserved intents (solver signs off-chain before intent creation). Some steps below describe the conceptual unreserved intent flow, which differs from the current implementation. For details on the differences between conception and implementation, see [requirements.md](requirements.md).

### 1) Requester deposit

Requester deposits to the connected chain the amount + fee token to an escrow contract owned by the verifier.
This deposit needs to be tracked by the intent which is why a specific smart contract is used to do it.
The requester calls the smart contract with the amount of token to swap + the pre-calculated fee.
The contract:

- verify the fee amount
- transfer the amount + fee token to the escrow pool
- use a unique `intent_id` (provided by the requester) to associate the escrow with the intent
- save the association with the intent_id and the swap amount in a table.

The intent_id allows to associate the request-intent with a transfer/escrow on the connected chains to verify that the requester has provided the escrow.

Remarks:
If the bridge transfer fails, how can the requester withdraw its tokens?

### 2) Requester initiates intent

**Note**: Current implementation uses reserved intents (solver signs off-chain before intent creation). See [requirements.md](requirements.md) for differences between conception and implementation.

Requester calls the request-intent on the M1 chain. The call creates an unreserved intent (conceptual - current implementation uses reserved intents).

Intent Data:

- requester public keys for both chains: identify the requester on both chains. There's always a M1 chain key in it.
- source chain nonce (conceptual - current implementation uses intent_id): Comes from the initial connected chain transfer done by the requester. Provided as a parameter of the Tx.
- Amount: amount of token to transfer on destination chain. Provided as a parameter of the Tx
- fee: fee of the transfer. Provided as a parameter of the Tx
- source → destination transfer info, for any connected chain to M1 chain transfer defined by the smart contract init, for M1 chain-> connected chain transfer, provided as a parameter of the Tx.
- expiry_time: timestamp where the intent will expire. Added by the contract. If no universal timestamp is available on the chain, provided by the Tx.
- signature of the pub keys (both chains), amount+fee, source→dest, nonce : used to verify the intent is owned by the requester.
- Id (intent_id): Hash of the data without the status: used to identify the intent.
- status: Intent status that can be: Unreserved, Reserved, Filled, Closed. Set to Unreserved when created (conceptual - current implementation creates reserved intents).

Verify that the initial Transfer Tx hash hasn't already been used for another intent. Use the nonce/intent_id to get the amount and save the id of the intent with it.
Verify that the intent amount is the same as the initial transfer Tx.
Save the intent data in a table with the id as key.

### 3) Solver detects unreserved intent

The solver monitors M1 chain event to detect the unreserved intent creation.

**TODO : TO BE UPDATED**: In current implementation, solver signs off-chain before intent creation, so this step happens earlier.

### 4) Solver verifies the intent and the requester's deposit

The solver verifies that the requester has transferred the correct funds to the Verifier's escrow.
The solver verifies that the intent's data are consistent:  signature, Id.

Remarks:
How to be sure the Requester doesn't reuse a Tx already attached to another intent. This verification should be done during the unreserved intent creation.

### 5) Solver lock collaterals

The solver locks in a M1 chain escrow the right amount of collateral to be authorized to reserve the intent. Defined by the lock ratio: Collateral = lock_ratio * amount.

**TODO : TO BE UPDATED**: Solver commitment is ensured through off-chain signature before intent creation, so this step happens earlier.

### 6) Solver lock intent

Solver locks the intent.
Use a first-come, first-served approach to lock the intent to a server to manage concurrent reservations.

**TODO : TO BE UPDATED**: Current implementation reserves intent at creation time based on off-chain solver signature.

### 7) M1 chain verify solver collateral

The M1 chain contract verifies that the solver has enough collateral to fill the request-intent. This verification should take into account all current filled request-intents managed by the solver.
The Solver M1 chain public key is added to the request-intent, and the status changes to reserved.

Steps 5, 6, and 7 are done in the same M1 chain smart contract call.

**Note**: Current implementation verifies solver signature from solver registry at intent creation time, not collateral.

### 8) Solver deposit requester amount on destination chain (= Hub chain)

The solver deposits the amount to the Requester's destination chain account. Can use a specific transfer Tx or a function developed for the intent framework.
The choice will depend on the proof we'll use to determine if the Solver has executed the transfer.

**Note**: In current Inflow flow, solver fulfills the request-intent on Hub chain (which is the destination chain), transferring desired tokens to requester.

### 9) Solver submits intent-filled

The solver submits to the verifier an intent-filled request. This request contains the intent id and the proof of the transfer to the requester.
The Solver submits its account on the connected chain to be able to transfer the funds.

Remarks:
The notification can be done on-chain using the same contract's call as the deposit (Step 8, in this case, the deposit generates an event monitored by the verifier) or call the verifier via a REST entry point.
I'm more in favor of the first behavior (on-chain notification) because it's easier to manage scenarios where notifications are missed. For example, if the  verifier is down, the solver needs to manage to resend the filled request, and this logic can be very error-prone (miss notification error, send several time the same notification, ...).

**TODO : TO BE UPDATED**: Current implementation uses on-chain events for verifier monitoring.

### Solver transfer execution proof

To verify the Solver transfer, the verifier needs a proof.
We can use the transfer Tx as proof, but we need to have a way to validate that the Tx hasn't been executed for another purpose, and in the end, the transfer hasn't been really done. As we can't add extra data to a transfer Tx, we need to use a specific function to do it.

**TODO : TO BE UPDATED**: Current implementation uses on-chain fulfillment transactions that include intent_id in calldata for verification.

In this case, we can develop a function that does the transfer and links it to the intent. So the Solver transfer and the intent filled should be done onchain using a specific function.

So use a direct RPC call to submit the intent filled we need to develop a specific proof generated during the transfer that the solver can use after the tx execution.

**TODO : TO BE UPDATED**: Current implementation uses on-chain fulfillment transactions that include intent_id in calldata for verification.

### 10) Verifier verifies the execution of the filled intent

The verifier verifies that the intent has been executed correctly. The amount has been transferred to the requester. Use the proof of the filled intent.
The verifier verifies that the Requester has transferred its funds to the connected chain. Need if the Requester and solver collude and don't do the initial transfer.

**TODO : TO BE UPDATED**: Current implementation validates fulfillment conditions including amount, recipient, solver match, and transaction success.

### 11) Verifier transfers the solver amount from escrow

The verifier transfers the amount + solver fee to the Solver account.

Deducts fixed protocol fee → Treasury

**TODO : TO BE UPDATED**: Current implementation uses verifier signature approval. Escrow release is done by anyone calling release function with verifier signature.

### 12) Verifier free solver collateral

The verifier releases the locked solver's collateral.

**TODO : TO BE UPDATED**: The fulfillment is already sufficient for inflow intents. So the verifier doesn't need to do anything. However the requester may never submit the escrow - in order to not keep the collateral hostage, a timeout mechanism (tight) should be used. A verifier action is still not needed.

### 13) Verifier closes the intent

The verifier updates the intent status to closed.
Updates exposure metrics.

Steps 11, 12, and 13 are done in the same M1 chain call.

**TODO : TO BE UPDATED**: No need, either it times out or is fulfilled. The intent is closed thus either by timeout or by fulfillment.
