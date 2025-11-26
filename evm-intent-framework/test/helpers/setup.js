const { ethers } = require("hardhat");

/// Shared test setup for IntentEscrow tests
/// Provides common fixtures and helper functions
async function setupIntentEscrowTests() {
  const [verifier, requester, solver] = await ethers.getSigners();
  const verifierWallet = verifier;

  // Deploy mock ERC20 token
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const token = await MockERC20.deploy("Test Token", "TEST", 18);
  await token.waitForDeployment();

  // Deploy escrow with verifier address
  const IntentEscrow = await ethers.getContractFactory("IntentEscrow");
  const escrow = await IntentEscrow.deploy(verifier.address);
  await escrow.waitForDeployment();

  const intentId = ethers.parseUnits("1", 0); // Simple intent ID

  return {
    escrow,
    token,
    verifier,
    requester,
    solver,
    intentId,
    verifierWallet
  };
}

/// Helper function to advance blockchain time for expiry testing
/// Uses Hardhat's evm_increaseTime to simulate time passage
/// @param seconds Number of seconds to advance
async function advanceTime(seconds) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}

/// Helper function to convert Aptos hex intent ID to EVM uint256
/// Removes 0x prefix if present and pads to 64 hex characters (32 bytes)
function hexToUint256(hexString) {
  const hex = hexString.startsWith('0x') ? hexString.slice(2) : hexString;
  return BigInt('0x' + hex.padStart(64, '0'));
}

module.exports = {
  setupIntentEscrowTests,
  advanceTime,
  hexToUint256
};

