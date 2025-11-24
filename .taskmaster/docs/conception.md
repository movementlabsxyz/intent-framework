# Conception

## Actor

- User : the user that want to swap some USDC from one chain to another using the intent process. One the the chain is always L1 mVt chain.
- Solver: actor that solve the swap intent. Can be anyone.
- Mvt: Represent the Mvt corporation that operate the intent application. Depending on the protocol but it can be a trusted entity if it runs some part of the protocol like the verifier.
- Hacker: a malicious actor that want to steal some fund or disturb the system.

## Use cases

### Users

- As a user, I want to swap some USDC from a chain A to mvt l1 so that I get my USDC on Mvt L1 fast and with low fee.
- As a user, I want to swap some USDC from mvt l1 to a chain so that I get my USDC on the destination chain fast and with low fee.
- As a User, I want a secure process so that I don't lose any token.

### Solver

- As a solver, I want to gain some token by participating to the intent system so that it exceed my operational cost.
- As a solver, I want a reliable solver process so that I don't have to spend time to operate my servers.
- As a solver, I want to be able to evaluate the benefit of taking an intent so that I don't solve intent that make me lose money.

### Mvt

- As Mvt I want to have a reliable and secure application so that Solver and user feel confident to use it.
- As Mvt I want that User use Move so that it increases the overall Mvt L1 usage.
- As Mvt I want to propose an open process where anybody can join so that it can grow without costing more to me.

### Hacker

- As a Hacker I want to steal some funds from the application to earn more money
- As a Hacker I want to disturb the process so that it affects its reputation.

## Protocol

TBD

```mermaid
sequenceDiagram
    participant User
    participant Source as Source Chain
    participant Movement as Movement Chain
    participant Solver
    participant Dest as Destination Chain
    participant Verifier

    User->>Source: Deposit 2001M to escrow
    User->>Movement: Create an unreserved intent
    Movement->>Solver: Detect unreserved intent
    Solver->>Source: Verify User deposit
    Solver->>Movement: Lock collateral
    Solver->>Movement: Reserve intent
    Dest->>Movement: Verify solver collateral to accept reservation
    Solver->>Dest: Deposit 2000M to User account
    Solver->>Movement: Submit filled intent
    Note left of Solver: Or call the verifier
    Solver->>Verifier: Submit filled intent
    Verifier->>Verifier: Get a filled intent
    Verifier->>Dest: Verify the execution
    Verifier->>Source: Transfer 2001M from escrow to solver account
    Verifier->>Movement: Free solver collateral
    Verifier->>Movement: Close the intent
```

## Scenarios

### A User make a swap from chain A to Mvt L1 chain

- Given the user owns the USDC that he want to transfer
- Given the user owns some Move to execute Tx on Mvt
- Given the user owns some chain A tokens
- Given the user can access to the chain and Mvt RPC

- When the user want to realize a swap from chain A to Mvt L1
- then the user send a Tx to Chain A to transfer the needed USDC + total fees token to an escrow. ( 1) User deposit protocol step)
- then the user send a intent Tx request to the Mvt chain. ( 2) User initiates intent protocol step)
- then the user wait for a confirmation of the swap
- then the user has received the requested amount of USDC in its Mvt account.

#### Possible issues

1. The user initial transfer is too less or too much.
The user didn't get the right expected amount.

Mitigations in the protocol:

1. the contract that create the intent, verify that the escrow transfer amount is the same as the intent.

#### Question

Does the fee are in USDC or in the chain token ?

### The Solver resolve a intent of a swap from chain A to Mvt L1 chain

- Given the solver owns some Move to execute Tx on Mvt
- Given the solver owns some chain A tokens
- Given the solver owns enough USDC on Mvt chain
- Given the solver can access to both chain RPC
- Given the solver is notified of intent request event.

- When the solver is notified of an user intent request Tx
- Then the solver verify the intent
- Then the solver reserve the intent
- If the intent reservation works
- Then the solver transfer on Mvt chain the requested USDC to the user account.
- The solver notifies that the intent has been solved.
- Then the solver waits that the amount of USDC + Solver fee is transferred to the solver account on the chain A

#### Possibles issues

The solver doesn't send the right amount of USDC to the user.
The solver get too less or too much USDC on chain A.
The solver is not notified of new intent request.
The solver resolve an intent that he hasn't been reserved.

### The Hacker steal some fund by doing a swap

- Given the hacker take the user role to so a swap

- When the Hacker want to realize a swap from chain A to Mvt L1
- (Optional) Then the Hacker send a Tx to Chain A that transfers too less USDC token to an escrow.
- Then the Hacker send a intent Tx request to the Mvt chain.
- Then the Hacker get more USDC on the Mvt L1 chain than he has provided.

Mitigation:
The solver verify that the needed intent amount (USDC requested amount + fee) has been transferred to the escrow.
How to be sure it's the right transfer Tx?

### The Hacker steal some fund by running a solver

- Given the hacker take the solver role to resolve an intent

- When the Hacker is notified of an user intent request Tx
- Then the Hacker reserve the intent
- (Optional) Then the hacker transfer less fund than expected to the user account.
- The Hacker notifies that the intent has been solved.
- Then the Hacker waits that the intent amount of USDC is transferred to the Hacker account on the chain A

### The Hacker steal the fund by been an User and a Solver

The Hacker run the too previous scenario to execute a false intent.

Mitigation:
The process that release the fund on chain A verify that the User has transferred the fund (USDC + fee) to the escrow and that the solver has transferred the fund to the user (USDC).
How to be sure it's the right transfer Txs?

## Risks

### Stole fund risk

- the escrow account can be hacked.
- the final transfer contract that send the intent USDC amount to the initial chain can be hacked and do false transfers.

### Disturb the service

- DOS attack on server (Solver or Verifier) or one of the blockchain.
- Create too much false intent.

## Protocol steps details

### 1) User deposit

User deposit to the source chain the amount + fee token to an escrow contract owned by the verifier.
This deposit need to be tracked by the intent that why a specific smart contract is used to do it.
The user call the smart contract with the amount of token to swap + the pre-calculated fee.
The contract:

- verify the fee amount
- transfer the amount + fee token to the escrow pool
- generate the unique nonce= String: `<chain number>_<unique chain nonce>`.
- save the association with the nonce and the swap amount in a table.
- increase the unique chain nonce
- return the source chain nonce.

The source chain nonce allow to associate the intent with a transfer on the source chain to verify that the user has effectively do the transfer.

Remarks:
If the bridge transfer fails, how can the user withdraw its tokens?

### 2) User initiates intent

User call the initiate intent on the movement chain. The call creates an unreserved intent.

Unreserved intent Data:

- user public keys for both chains: identify the user on both chains. There's always a Mvt key in it.
- source chain nonce: Come from the initial source chain transfer done by the user. Provided as a parameters of the Tx.
- Amount: amount of token to transfer on destination chain. Provided as a parameters of the Tx
- fee: fee of the transfer. Provided as a parameters of the Tx
- source → destination transfer info, for any chain to Mvt transfer defined by the smart contract init, for Mvt-> chain transfer, provided as a parameters of the Tx.
- expiry_time: timestamp where the intent will expire. Add by the contract. If no universal timestamp is available on the chain, provided by the Tx.
- signature of the pub keys (both chains), amount+fee, source→dest, nonce : use to verify the intent is owned by the user.
- Id : Hash of the data without the status: use to identify the intent.
- status: Intent status that can be: Unreserved, Reserved, Filled, Closed. Set to Unreserved when created.

Verify that the initial Transfer Tx hash hasn't already been used for another intent. Use the nonce to get the amount and save the id of the intent with it.
Verify that the intent amount is the same as the initial transfer Tx.
Save the intent data in a table with the id as key.

### 3) Solver detects unreserved intent

The solver monitors Mvt chain event to detect the unreserved intent creation.

### 4) Solver verifies the intent and the user's deposit

The solver verifies that the user has transferred the correct funds to the Verifier's escrow.
The solver verifies that the intent's data are consistent:  signature, Id.

Remarks:
How to be sure the User doesn't reuse a Tx already attached to another intent. This verification should be done during the unreserved intent creation.

### 5) Solver lock collaterals

The solver locks in a Mvt chain escrow the right amount of collateral to be authorized to reserve the intent. Defined by the lock ratio: Collateral = lock_ratio * amount.

### 6) Solver lock intent

Solver locks the intent.
Use a first-come, first-served approach to lock the intent to a server to manage concurrent reservations.

### 7) Mvt chain verify solver collateral

The Mvt contract verifies that the solver has enough collateral to fill the intent. This verification should take into account all current filled intent managed by the solver.
The Solver Mvt public key is added to the intent, and the status changes to reserved.

Steps 5, 7, and 7 are done in the same Mvt smart contract call.

### 8) Solver deposit user amount on destination chain

The solver deposits the amount to the User's destination chain account. Can use a specific transfer Tx or a function developed for the intent framework.
The choice will depend on the proof we'll use to determine if the Solver has executed the transfer.

### 9) Solver submits intent-filled

The solver submits to the verifier an intent-filled request. This request contains the intent id and the proof of the transfer to the user.
The Solver submits its account on the source chain to be able to transfer the funds.

Remarks:
The notification can be done on-chain using the same contract's call as the deposit (Step 8, in this case, the deposit generates an event monitored by the verifier) or call the verifier via a REST entry point.
I'm more in favor of the first behavior (on-chain notification) because it's easier to manage scenarios where notifications are missed. For example, if the  verifier is down, the solver needs to manage to resend the filled request, and this logic can be very error-prone (miss notification error, send several time the same notification, ...).

### Solver transfer execution proof

To verify the Solver transfer, the verifier needs a proof.
We can use the transfer Tx as proof, but we need to have a way to validate that the Tx hasn't been executed for another purpose, and in the end, the transfer hasn't been really done. As we can't add extra data to a transfer Tx, we need to use a specific function to do it.

In this case, we can develop a function that does the transfer and links it to the intent. So the Solver transfer and the intent filled should be done onchain using a specific function.

So use a direct RPC call to submit the intent filled we need to develop a specific poof generated during the transfer that the solver can use after the tx execution.

### 10) Verifier verifies the execution of the filled intent

The verifier verifies that the intent has been executed correctly. The amount has been transferred to the user. Use the proof of the filled intent.
The verifier verifies that the User has transferred its funds to the source chain. Need if the User and server collude and don't do the initial transfer.

### 11) Verifier transfers the solver amount from escrow

The verifier transfers the amount + solver fee to the Solver account.

Deducts fixed protocol fee → Treasury

### 12) Verifier free solver collateral

The verifier releases the locked solver's collateral.

### 13) Verifier closes the intent

The verifier updates the intent status to closed.
Updates exposure metrics.

Steps 11, 12, and 13 are done in the same Mvt chain call.
