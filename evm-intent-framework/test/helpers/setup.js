const { ethers } = require("hardhat");

/// Shared test setup for IntentVault tests
/// Provides common fixtures and helper functions
async function setupIntentVaultTests() {
  const [verifier, maker, solver] = await ethers.getSigners();
  const verifierWallet = verifier;

  // Deploy mock ERC20 token
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const token = await MockERC20.deploy("Test Token", "TEST");
  await token.waitForDeployment();

  // Deploy vault with verifier address
  const IntentVault = await ethers.getContractFactory("IntentVault");
  const vault = await IntentVault.deploy(verifier.address);
  await vault.waitForDeployment();

  const intentId = ethers.parseUnits("1", 0); // Simple intent ID

  return {
    vault,
    token,
    verifier,
    maker,
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
  setupIntentVaultTests,
  advanceTime,
  hexToUint256
};

