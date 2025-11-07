const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentVaultTests, hexToUint256 } = require("./helpers/setup");

describe("IntentVault - Cross-Chain Intent ID Conversion", function () {
  let vault;
  let token;
  let maker;
  let intentId;

  beforeEach(async function () {
    const fixtures = await setupIntentVaultTests();
    vault = fixtures.vault;
    token = fixtures.token;
    maker = fixtures.maker;
    intentId = fixtures.intentId;
  });

  /// Test: Aptos Hex to EVM uint256 Conversion
  /// Verifies that intent IDs from Aptos hex format can be converted and used in EVM vault operations.
  it("Should handle Aptos hex intent ID conversion to EVM uint256", async function () {
    // Aptos intent ID in hex format (smaller than 32 bytes)
    const aptosIntentIdHex = "0x1234";
    const evmIntentId = hexToUint256(aptosIntentIdHex);

    // Initialize vault with converted intent ID
    await vault.connect(maker).initializeVault(evmIntentId, token.target);

    // Verify vault was initialized correctly
    const vaultData = await vault.getVault(evmIntentId);
    expect(vaultData.maker).to.equal(maker.address);
    expect(vaultData.token).to.equal(token.target);

    // Deposit and verify it works with converted intent ID
    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount);
    await token.connect(maker).approve(vault.target, amount);
    await vault.connect(maker).deposit(evmIntentId, amount);

    expect(await token.balanceOf(vault.target)).to.equal(amount);
  });

  /// Test: Intent ID Boundary Values
  /// Verifies that the contract handles boundary intent ID values correctly.
  it("Should handle intent ID boundary values", async function () {
    // Test maximum uint256 value
    const maxIntentId = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
    await vault.connect(maker).initializeVault(maxIntentId, token.target);
    const maxVaultData = await vault.getVault(maxIntentId);
    expect(maxVaultData.maker).to.equal(maker.address);

    // Test zero value
    const zeroIntentId = 0n;
    await vault.connect(maker).initializeVault(zeroIntentId, token.target);
    const zeroVaultData = await vault.getVault(zeroIntentId);
    expect(zeroVaultData.maker).to.equal(maker.address);

    // Test edge value (2^128 - 1)
    const edgeIntentId = BigInt("0xffffffffffffffffffffffffffffffff");
    await vault.connect(maker).initializeVault(edgeIntentId, token.target);
    const edgeVaultData = await vault.getVault(edgeIntentId);
    expect(edgeVaultData.maker).to.equal(maker.address);
  });

  /// Test: Intent ID Zero Padding
  /// Verifies that shorter intent IDs are properly left-padded with zeros.
  it("Should handle intent ID zero padding correctly", async function () {
    // Test various short hex strings that need padding
    const shortHexIds = [
      "0x1",
      "0x12",
      "0x123",
      "0x1234",
      "0x12345",
      "0x1234567890abcdef"
    ];

    for (const hexId of shortHexIds) {
      const paddedIntentId = hexToUint256(hexId);
      const expectedValue = BigInt(hexId);

      // Verify padding produces correct value
      expect(paddedIntentId).to.equal(expectedValue);

      // Verify vault operations work with padded intent ID
      await vault.connect(maker).initializeVault(paddedIntentId, token.target);
      const vaultData = await vault.getVault(paddedIntentId);
      expect(vaultData.maker).to.equal(maker.address);
    }
  });

  /// Test: Multiple Intent IDs from Different Formats
  /// Verifies that multiple vaults can be created with intent IDs from different Aptos formats.
  it("Should handle multiple intent IDs from different Aptos formats", async function () {
    const intentIds = [
      hexToUint256("0x1"),
      hexToUint256("0x1234"),
      hexToUint256("0xabcdef"),
      hexToUint256("0x1234567890abcdef"),
      ethers.parseUnits("1000000", 0), // Direct uint256 format
      ethers.parseUnits("999999", 0) // Large number format
    ];

    // Initialize vaults with different intent ID formats
    for (let i = 0; i < intentIds.length; i++) {
      await vault.connect(maker).initializeVault(intentIds[i], token.target);
      const vaultData = await vault.getVault(intentIds[i]);
      expect(vaultData.maker).to.equal(maker.address);
      expect(vaultData.token).to.equal(token.target);
    }

    // Verify all vaults are independent
    expect(await vault.getVault(intentIds[0])).to.not.be.undefined;
    expect(await vault.getVault(intentIds[1])).to.not.be.undefined;
    expect(await vault.getVault(intentIds[2])).to.not.be.undefined;
  });
});

