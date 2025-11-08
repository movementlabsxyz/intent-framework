# EVM Intent Framework

Escrow contract for cross-chain intents that releases funds to solvers when verifier signatures check out.

## Overview

The `IntentEscrow` contract implements a secure escrow system where:
- **Makers** deposit ERC20 tokens into escrows tied to intent IDs
- **Solvers** can claim funds after providing a valid verifier signature
- **Verifiers** sign approval messages off-chain after verifying cross-chain conditions
- **Makers** can cancel and reclaim funds after expiry

## Architecture

ECDSA signature verification similar to the Aptos escrow system.

### Flow

1. **Initialize**: Maker creates an escrow for an intent ID with a token (expiry is contract-defined: 1 hour)
2. **Deposit**: Maker deposits ERC20 tokens into the escrow
3. **Verify** (off-chain): Verifier monitors conditions and signs approval
4. **Claim**: Solver provides verifier signature to claim funds
5. **Cancel** (optional): Maker can cancel and reclaim after expiry

## Signature Verification

The verifier signs a message with the following format:

```
messageHash = keccak256(abi.encodePacked(intentId, approvalValue))
ethSignedMessage = keccak256("\x19Ethereum Signed Message:\n32" || messageHash)
```

Where:
- `intentId`: The unique intent identifier (uint256)
- `approvalValue`: Must be `1` to approve (uint8)

The contract uses `ecrecover()` to verify the signature matches the authorized verifier address.

## Contract Interface

### Functions

```solidity
// Initialize an escrow for an intent (expiry is contract-defined: 1 hour)
function initializeEscrow(uint256 intentId, address token) external

// Deposit tokens into escrow
function deposit(uint256 intentId, uint256 amount) external

// Claim funds with verifier signature
function claim(uint256 intentId, uint8 approvalValue, bytes memory signature) external

// Cancel escrow and reclaim funds (maker only, after expiry)
function cancel(uint256 intentId) external

// Get escrow data
function getEscrow(uint256 intentId) external view returns (address, address, uint256, bool, uint256)
```

### Events

- `EscrowInitialized(uint256 indexed intentId, address indexed escrow, address indexed maker, address token)`
- `DepositMade(uint256 indexed intentId, address indexed user, uint256 amount, uint256 total)`
- `EscrowClaimed(uint256 indexed intentId, address indexed solver, uint256 amount)`
- `EscrowCancelled(uint256 indexed intentId, address indexed maker, uint256 amount)`

## Setup

```bash
npm install
npx hardhat compile
npx hardhat test
```

## Usage Example

```javascript
const { ethers } = require("hardhat");

// Deploy escrow with verifier address
const IntentEscrow = await ethers.getContractFactory("IntentEscrow");
const escrow = await IntentEscrow.deploy(verifierAddress);

// Maker initializes escrow (expiry is contract-defined: 1 hour)
await escrow.connect(maker).initializeEscrow(intentId, tokenAddress);

// Maker deposits tokens
await token.connect(maker).approve(escrow.address, amount);
await escrow.connect(maker).deposit(intentId, amount);

// Verifier signs approval (off-chain)
const messageHash = ethers.solidityPackedKeccak256(
  ["uint256", "uint8"],
  [intentId, 1]
);
const signature = await verifier.signMessage(ethers.getBytes(messageHash));

// Solver claims with signature
await escrow.connect(solver).claim(intentId, 1, signature);
```

## Security Considerations

- **Signature Verification**: Only signatures from the authorized verifier address are accepted
- **Approval Value**: Must be exactly `1` to approve (prevents replay with rejection signatures)
- **Reentrancy**: Uses OpenZeppelin's SafeERC20 to prevent reentrancy attacks
- **Access Control**: Only maker can cancel escrow (after expiry)
- **Immutable Verifier**: Verifier address is set in constructor and cannot be changed

## Testing

Run tests with:
```bash
npx hardhat test
```

Tests cover:
- Escrow initialization
- Token deposits
- Claiming with valid/invalid signatures
- Cancellation by maker (after expiry)
- Expiry enforcement
- Error cases (already claimed, unauthorized, etc.)

## Differences from Solana Version

1. **Signature Verification**: Added ECDSA signature verification (Solana version doesn't verify signatures)
2. **ERC20 Support**: Works with any ERC20 token (Solana uses specific token accounts)
3. **Expiry Handling**: Expiry is contract-defined (1 hour) and enforced on-chain (claims blocked after expiry, cancellation only allowed after expiry)

