const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentEscrowTests } = require("./helpers/setup");

describe("IntentEscrow - Edge Cases", function () {
  let escrow;
  let token;
  let verifierWallet;
  let requester;
  let solver;
  let intentId;

  beforeEach(async function () {
    const fixtures = await setupIntentEscrowTests();
    escrow = fixtures.escrow;
    token = fixtures.token;
    verifierWallet = fixtures.verifierWallet;
    requester = fixtures.requester;
    solver = fixtures.solver;
    intentId = fixtures.intentId;
  });

  /// Test: Maximum uint256 Values
  /// Verifies that createEscrow handles maximum uint256 values for both amounts and intent IDs.
  /// Why: Edge case testing ensures the contract handles boundary values without overflow or underflow.
  it("Should handle maximum uint256 values for amounts and intent IDs", async function () {
    const maxAmount = ethers.MaxUint256;
    const maxIntentId = ethers.MaxUint256;
    
    // Mint maximum amount
    await token.mint(requester.address, maxAmount);
    await token.connect(requester).approve(escrow.target, maxAmount);

    // Create escrow with max intent ID and max amount
    await expect(escrow.connect(requester).createEscrow(maxIntentId, token.target, maxAmount, solver.address))
      .to.emit(escrow, "EscrowInitialized");
    
    const escrowData = await escrow.getEscrow(maxIntentId);
    expect(escrowData.amount).to.equal(maxAmount);
    expect(escrowData.requester).to.equal(requester.address);
  });

  /// Test: Empty Deposit Scenarios
  /// Verifies edge cases around minimum deposit amounts (1 wei).
  /// Why: Ensures the contract accepts the minimum valid amount (1 wei) without rejecting it as zero.
  it("Should handle minimum deposit amount (1 wei)", async function () {
    const minAmount = 1n; // 1 wei
    const testIntentId = intentId + 1n;
    
    await token.mint(requester.address, minAmount);
    await token.connect(requester).approve(escrow.target, minAmount);

    await expect(escrow.connect(requester).createEscrow(testIntentId, token.target, minAmount, solver.address))
      .to.emit(escrow, "EscrowInitialized");
    
    const escrowData = await escrow.getEscrow(testIntentId);
    expect(escrowData.amount).to.equal(minAmount);
  });

  /// Test: Multiple Escrows Per Requester
  /// Verifies that a requester can create multiple escrows with different intent IDs.
  /// Why: Requesters may need multiple concurrent escrows for different intents. State isolation must be maintained.
  it("Should allow requester to create multiple escrows", async function () {
    const numEscrows = 10;
    const amount = ethers.parseEther("100");
    const totalAmount = amount * BigInt(numEscrows);
    
    await token.mint(requester.address, totalAmount);
    await token.connect(requester).approve(escrow.target, totalAmount);

    // Create multiple escrows with sequential intent IDs
    for (let i = 0; i < numEscrows; i++) {
      const testIntentId = intentId + BigInt(i);
      await expect(escrow.connect(requester).createEscrow(testIntentId, token.target, amount, solver.address))
        .to.emit(escrow, "EscrowInitialized");
      
      const escrowData = await escrow.getEscrow(testIntentId);
      expect(escrowData.amount).to.equal(amount);
      expect(escrowData.requester).to.equal(requester.address);
    }
  });

  /// Test: Gas Limit Scenarios
  /// Verifies gas consumption for large operations (multiple escrows, large amounts).
  /// Why: Gas efficiency is critical for user experience. Operations must stay within reasonable gas limits.
  it("Should handle gas consumption for large operations", async function () {
    const numEscrows = 5;
    const amount = ethers.parseEther("1000");
    const totalAmount = amount * BigInt(numEscrows);
    
    await token.mint(requester.address, totalAmount);
    await token.connect(requester).approve(escrow.target, totalAmount);

    // Create multiple escrows and measure gas
    const gasEstimates = [];
    for (let i = 0; i < numEscrows; i++) {
      const testIntentId = intentId + BigInt(i);
      const tx = await escrow.connect(requester).createEscrow(testIntentId, token.target, amount, solver.address);
      const receipt = await tx.wait();
      gasEstimates.push(receipt.gasUsed);
    }

    // Verify all transactions succeeded
    expect(gasEstimates.length).to.equal(numEscrows);
    // Verify gas usage is reasonable (less than 500k gas per transaction)
    gasEstimates.forEach(gas => {
      expect(gas).to.be.below(500000n);
    });
  });

  /// Test: Concurrent Operations
  /// Verifies that multiple simultaneous escrow operations can be handled correctly.
  /// Why: Real-world usage involves concurrent operations. The contract must handle them without state corruption.
  it("Should handle concurrent escrow operations", async function () {
    const numEscrows = 5;
    const amount = ethers.parseEther("100");
    const totalAmount = amount * BigInt(numEscrows);
    
    await token.mint(requester.address, totalAmount);
    await token.connect(requester).approve(escrow.target, totalAmount);

    // Create multiple escrows concurrently (all in same block)
    const promises = [];
    for (let i = 0; i < numEscrows; i++) {
      const testIntentId = intentId + BigInt(i);
      promises.push(escrow.connect(requester).createEscrow(testIntentId, token.target, amount, solver.address));
    }

    // Wait for all transactions
    const results = await Promise.all(promises);
    
    // Verify all succeeded
    expect(results.length).to.equal(numEscrows);
    
    // Verify all escrows were created correctly
    for (let i = 0; i < numEscrows; i++) {
      const testIntentId = intentId + BigInt(i);
      const escrowData = await escrow.getEscrow(testIntentId);
      expect(escrowData.amount).to.equal(amount);
      expect(escrowData.requester).to.equal(requester.address);
    }
  });
});

