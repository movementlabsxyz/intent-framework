# EVM Intent Framework

Vault contract for cross-chain intents that releases funds to solvers when verifier signatures check out.

## Overview

The `IntentVault` contract implements a secure escrow system where:
- **Makers** deposit ERC20 tokens into vaults tied to intent IDs
- **Solvers** can claim funds after providing a valid verifier signature
- **Verifiers** sign approval messages off-chain after verifying cross-chain conditions
- **Makers** can cancel and reclaim funds after expiry

## Architecture

Based on the Solana vault pattern (`movement_intent/solana-vault`) but adds ECDSA signature verification similar to the Aptos escrow system.

### Flow

1. **Initialize**: Maker creates a vault for an intent ID with a token and expiry
2. **Deposit**: Maker deposits ERC20 tokens into the vault
3. **Verify** (off-chain): Verifier monitors conditions and signs approval
4. **Claim**: Solver provides verifier signature to claim funds
5. **Cancel** (optional): Maker can cancel and reclaim if needed

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
// Initialize a vault for an intent
function initializeVault(uint256 intentId, address token, uint256 expiry) external

// Deposit tokens into vault
function deposit(uint256 intentId, uint256 amount) external

// Claim funds with verifier signature
function claim(uint256 intentId, uint8 approvalValue, bytes memory signature) external

// Cancel vault and reclaim funds (maker only)
function cancel(uint256 intentId) external

// Get vault data
function getVault(uint256 intentId) external view returns (address, address, uint256, bool, uint256)
```

### Events

- `VaultInitialized(uint256 indexed intentId, address indexed vault, address indexed maker, address token)`
- `DepositMade(uint256 indexed intentId, address indexed user, uint256 amount, uint256 total)`
- `VaultClaimed(uint256 indexed intentId, address indexed solver, uint256 amount)`
- `VaultCancelled(uint256 indexed intentId, address indexed maker, uint256 amount)`

## Setup

```bash
npm install
npx hardhat compile
npx hardhat test
```

## Usage Example

```javascript
const { ethers } = require("hardhat");

// Deploy vault with verifier address
const IntentVault = await ethers.getContractFactory("IntentVault");
const vault = await IntentVault.deploy(verifierAddress);

// Maker initializes vault
await vault.connect(maker).initializeVault(intentId, tokenAddress, expiry);

// Maker deposits tokens
await token.connect(maker).approve(vault.address, amount);
await vault.connect(maker).deposit(intentId, amount);

// Verifier signs approval (off-chain)
const messageHash = ethers.solidityPackedKeccak256(
  ["uint256", "uint8"],
  [intentId, 1]
);
const signature = await verifier.signMessage(ethers.getBytes(messageHash));

// Solver claims with signature
await vault.connect(solver).claim(intentId, 1, signature);
```

## Security Considerations

- **Signature Verification**: Only signatures from the authorized verifier address are accepted
- **Approval Value**: Must be exactly `1` to approve (prevents replay with rejection signatures)
- **Reentrancy**: Uses OpenZeppelin's SafeERC20 to prevent reentrancy attacks
- **Access Control**: Only maker can cancel vault
- **Immutable Verifier**: Verifier address is set in constructor and cannot be changed

## Testing

Run tests with:
```bash
npx hardhat test
```

Tests cover:
- Vault initialization
- Token deposits
- Claiming with valid/invalid signatures
- Cancellation by maker
- Error cases (already claimed, unauthorized, etc.)

## Differences from Solana Version

1. **Signature Verification**: Added ECDSA signature verification (Solana version doesn't verify signatures)
2. **ERC20 Support**: Works with any ERC20 token (Solana uses specific token accounts)
3. **Expiry Handling**: Expiry is stored but not enforced on-chain (maker controls cancel)

