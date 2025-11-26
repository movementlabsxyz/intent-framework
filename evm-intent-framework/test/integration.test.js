const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentEscrowTests, advanceTime } = require("./helpers/setup");

describe("IntentEscrow - Integration Tests", function () {
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

  /// Test: Complete Deposit to Claim Workflow
  /// Verifies the full workflow from escrow creation through claim.
  /// Why: Integration test ensures all components work together correctly in the happy path.
  it("Should complete full deposit to claim workflow", async function () {
    const amount = ethers.parseEther("100");
    
    // Step 1: Mint tokens and approve
    await token.mint(requester.address, amount);
    await token.connect(requester).approve(escrow.target, amount);
    
    // Step 2: Create escrow and verify EscrowInitialized event
    await expect(escrow.connect(requester).createEscrow(intentId, token.target, amount, solver.address))
      .to.emit(escrow, "EscrowInitialized")
      .withArgs(intentId, escrow.target, requester.address, token.target, solver.address);
    
    // Step 3: Verify escrow state
    const escrowDataBefore = await escrow.getEscrow(intentId);
    expect(escrowDataBefore.requester).to.equal(requester.address);
    expect(escrowDataBefore.amount).to.equal(amount);
    expect(escrowDataBefore.isClaimed).to.equal(false);
    expect(await token.balanceOf(escrow.target)).to.equal(amount);
    
    // Step 4: Generate verifier signature for claim
    // Signature is over intentId only (signature itself is the approval)
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256"],
      [intentId]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));
    
    // Step 5: Claim escrow and verify EscrowClaimed event
    expect(await token.balanceOf(solver.address)).to.equal(0);
    await expect(escrow.connect(solver).claim(intentId, signature))
      .to.emit(escrow, "EscrowClaimed")
      .withArgs(intentId, solver.address, amount);
    
    // Step 6: Verify final state
    const escrowDataAfter = await escrow.getEscrow(intentId);
    expect(escrowDataAfter.isClaimed).to.equal(true);
    expect(escrowDataAfter.amount).to.equal(0);
    expect(await token.balanceOf(solver.address)).to.equal(amount);
    expect(await token.balanceOf(escrow.target)).to.equal(0);
    expect(await token.balanceOf(requester.address)).to.equal(0);
  });

  /// Test: Multi-Token Scenarios
  /// Verifies that the escrow works with different ERC20 tokens.
  /// Why: The escrow must support any ERC20 token, not just a single token type.
  it("Should handle multiple different ERC20 tokens", async function () {
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const token1 = await MockERC20.deploy("Token One", "TKN1", 18);
    await token1.waitForDeployment();
    const token2 = await MockERC20.deploy("Token Two", "TKN2", 18);
    await token2.waitForDeployment();
    const token3 = await MockERC20.deploy("Token Three", "TKN3", 18);
    await token3.waitForDeployment();
    
    const amount1 = ethers.parseEther("100");
    const amount2 = ethers.parseEther("200");
    const amount3 = ethers.parseEther("300");
    
    const intentId1 = intentId;
    const intentId2 = intentId + 1n;
    const intentId3 = intentId + 2n;
    
    // Create escrows with different tokens
    await token1.mint(requester.address, amount1);
    await token1.connect(requester).approve(escrow.target, amount1);
    await escrow.connect(requester).createEscrow(intentId1, token1.target, amount1, solver.address);
    
    await token2.mint(requester.address, amount2);
    await token2.connect(requester).approve(escrow.target, amount2);
    await escrow.connect(requester).createEscrow(intentId2, token2.target, amount2, solver.address);
    
    await token3.mint(requester.address, amount3);
    await token3.connect(requester).approve(escrow.target, amount3);
    await escrow.connect(requester).createEscrow(intentId3, token3.target, amount3, solver.address);
    
    // Verify all escrows were created correctly
    const escrow1 = await escrow.getEscrow(intentId1);
    const escrow2 = await escrow.getEscrow(intentId2);
    const escrow3 = await escrow.getEscrow(intentId3);
    
    expect(escrow1.token).to.equal(token1.target);
    expect(escrow1.amount).to.equal(amount1);
    expect(escrow2.token).to.equal(token2.target);
    expect(escrow2.amount).to.equal(amount2);
    expect(escrow3.token).to.equal(token3.target);
    expect(escrow3.amount).to.equal(amount3);
    
    // Verify balances
    expect(await token1.balanceOf(escrow.target)).to.equal(amount1);
    expect(await token2.balanceOf(escrow.target)).to.equal(amount2);
    expect(await token3.balanceOf(escrow.target)).to.equal(amount3);
  });

  /// Test: Comprehensive Event Emission
  /// Verifies that all events are emitted with correct parameters.
  /// Why: Events are critical for off-chain monitoring and indexing. Incorrect events break integrations.
  it("Should emit all events with correct parameters", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(requester.address, amount);
    await token.connect(requester).approve(escrow.target, amount);
    
    // Test EscrowInitialized event
    await expect(escrow.connect(requester).createEscrow(intentId, token.target, amount, solver.address))
      .to.emit(escrow, "EscrowInitialized")
      .withArgs(intentId, escrow.target, requester.address, token.target, solver.address);
    
    // Test EscrowClaimed event
    // Signature is over intentId only (signature itself is the approval)
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256"],
      [intentId]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));
    
    await expect(escrow.connect(solver).claim(intentId, signature))
      .to.emit(escrow, "EscrowClaimed")
      .withArgs(intentId, solver.address, amount);
  });

  /// Test: Complete Cancellation Workflow
  /// Verifies the full workflow from escrow creation through cancellation after expiry.
  /// Why: Integration test ensures the cancellation flow works end-to-end after expiry.
  it("Should complete full cancellation workflow", async function () {
    const amount = ethers.parseEther("100");
    
    // Step 1: Create escrow
    await token.mint(requester.address, amount);
    await token.connect(requester).approve(escrow.target, amount);
    
    await expect(escrow.connect(requester).createEscrow(intentId, token.target, amount, solver.address))
      .to.emit(escrow, "EscrowInitialized")
      .withArgs(intentId, escrow.target, requester.address, token.target, solver.address);
    
    // Step 2: Verify escrow state before expiry
    const escrowDataBefore = await escrow.getEscrow(intentId);
    expect(escrowDataBefore.requester).to.equal(requester.address);
    expect(escrowDataBefore.amount).to.equal(amount);
    expect(escrowDataBefore.isClaimed).to.equal(false);
    expect(await token.balanceOf(escrow.target)).to.equal(amount);
    
    // Step 3: Advance time past expiry (1 hour = 3600 seconds)
    await advanceTime(3601);
    
    // Step 4: Cancel escrow and verify EscrowCancelled event
    await expect(escrow.connect(requester).cancel(intentId))
      .to.emit(escrow, "EscrowCancelled")
      .withArgs(intentId, requester.address, amount);
    
    // Step 5: Verify final state
    const escrowDataAfter = await escrow.getEscrow(intentId);
    expect(escrowDataAfter.amount).to.equal(0);
    expect(await token.balanceOf(requester.address)).to.equal(amount);
    expect(await token.balanceOf(escrow.target)).to.equal(0);
  });
});

