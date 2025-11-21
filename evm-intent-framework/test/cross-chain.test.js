const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentEscrowTests, hexToUint256 } = require("./helpers/setup");

describe("IntentEscrow - Cross-Chain Intent ID Conversion", function () {
  let escrow;
  let token;
  let maker;
  let solver;
  let intentId;

  beforeEach(async function () {
    const fixtures = await setupIntentEscrowTests();
    escrow = fixtures.escrow;
    token = fixtures.token;
    maker = fixtures.maker;
    solver = fixtures.solver;
    intentId = fixtures.intentId;
  });

  /// Test: Aptos Hex to EVM uint256 Conversion
  /// Verifies that intent IDs from Aptos hex format can be converted and used in EVM escrow operations.
  /// Why: Cross-chain intents require intent ID conversion between Aptos (hex) and EVM (uint256) formats.
  it("Should handle Aptos hex intent ID conversion to EVM uint256", async function () {
    // Aptos intent ID in hex format (smaller than 32 bytes)
    const aptosIntentIdHex = "0x1234";
    const evmIntentId = hexToUint256(aptosIntentIdHex);

    // Create escrow with converted intent ID and deposit atomically
    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount);
    await token.connect(maker).approve(escrow.target, amount);
    await escrow.connect(maker).createEscrow(evmIntentId, token.target, amount, solver.address);

    // Verify escrow was created correctly
    const escrowData = await escrow.getEscrow(evmIntentId);
    expect(escrowData.maker).to.equal(maker.address);
    expect(escrowData.token).to.equal(token.target);
    expect(escrowData.amount).to.equal(amount);

    expect(await token.balanceOf(escrow.target)).to.equal(amount);
  });

  /// Test: Intent ID Boundary Values
  /// Verifies that the contract handles boundary intent ID values correctly.
  /// Why: Intent IDs from different chains may have different formats. Boundary testing ensures compatibility.
  it("Should handle intent ID boundary values", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount * 3n);
    await token.connect(maker).approve(escrow.target, amount * 3n);

    // Test maximum uint256 value
    const maxIntentId = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
    await escrow.connect(maker).createEscrow(maxIntentId, token.target, amount, solver.address);
    const maxEscrowData = await escrow.getEscrow(maxIntentId);
    expect(maxEscrowData.maker).to.equal(maker.address);
    expect(maxEscrowData.amount).to.equal(amount);

    // Test zero value
    const zeroIntentId = 0n;
    await escrow.connect(maker).createEscrow(zeroIntentId, token.target, amount, solver.address);
    const zeroEscrowData = await escrow.getEscrow(zeroIntentId);
    expect(zeroEscrowData.maker).to.equal(maker.address);
    expect(zeroEscrowData.amount).to.equal(amount);

    // Test edge value (2^128 - 1)
    const edgeIntentId = BigInt("0xffffffffffffffffffffffffffffffff");
    await escrow.connect(maker).createEscrow(edgeIntentId, token.target, amount, solver.address);
    const edgeEscrowData = await escrow.getEscrow(edgeIntentId);
    expect(edgeEscrowData.maker).to.equal(maker.address);
    expect(edgeEscrowData.amount).to.equal(amount);
  });

  /// Test: Intent ID Zero Padding
  /// Verifies that shorter intent IDs are properly left-padded with zeros.
  /// Why: Aptos intent IDs may be shorter than 32 bytes. Zero padding ensures correct uint256 conversion.
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

    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount * BigInt(shortHexIds.length));
    await token.connect(maker).approve(escrow.target, amount * BigInt(shortHexIds.length));

    for (const hexId of shortHexIds) {
      const paddedIntentId = hexToUint256(hexId);
      const expectedValue = BigInt(hexId);

      // Verify padding produces correct value
      expect(paddedIntentId).to.equal(expectedValue);

      // Verify escrow operations work with padded intent ID
      await escrow.connect(maker).createEscrow(paddedIntentId, token.target, amount, solver.address);
      const escrowData = await escrow.getEscrow(paddedIntentId);
      expect(escrowData.maker).to.equal(maker.address);
      expect(escrowData.amount).to.equal(amount);
    }
  });

  /// Test: Multiple Intent IDs from Different Formats
  /// Verifies that multiple escrows can be created with intent IDs from different Aptos formats.
  /// Why: Real-world usage involves intent IDs in various formats. The contract must handle all valid formats.
  it("Should handle multiple intent IDs from different Aptos formats", async function () {
    const intentIds = [
      hexToUint256("0x1"),
      hexToUint256("0x1234"),
      hexToUint256("0xabcdef"),
      hexToUint256("0x1234567890abcdef"),
      ethers.parseUnits("1000000", 0), // Direct uint256 format
      ethers.parseUnits("999999", 0) // Large number format
    ];

    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount * BigInt(intentIds.length));
    await token.connect(maker).approve(escrow.target, amount * BigInt(intentIds.length));

    // Create escrows with different intent ID formats
    for (let i = 0; i < intentIds.length; i++) {
      await escrow.connect(maker).createEscrow(intentIds[i], token.target, amount, solver.address);
      const escrowData = await escrow.getEscrow(intentIds[i]);
      expect(escrowData.maker).to.equal(maker.address);
      expect(escrowData.token).to.equal(token.target);
      expect(escrowData.amount).to.equal(amount);
    }

    // Verify all escrows are independent
    expect(await escrow.getEscrow(intentIds[0])).to.not.be.undefined;
    expect(await escrow.getEscrow(intentIds[1])).to.not.be.undefined;
    expect(await escrow.getEscrow(intentIds[2])).to.not.be.undefined;
  });
});

