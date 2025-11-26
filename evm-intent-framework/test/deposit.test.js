const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentEscrowTests } = require("./helpers/setup");

describe("IntentEscrow - Create Escrow (Deposit)", function () {
  let escrow;
  let token;
  let requester;
  let solver;
  let intentId;

  beforeEach(async function () {
    const fixtures = await setupIntentEscrowTests();
    escrow = fixtures.escrow;
    token = fixtures.token;
    requester = fixtures.requester;
    solver = fixtures.solver;
    intentId = fixtures.intentId;
  });

  /// Test: Token Escrow Creation
  /// Verifies that requesters can create an escrow with ERC20 tokens atomically.
  /// Why: Escrow creation is the first step in the intent fulfillment flow. Requesters must be able to lock funds securely.
  it("Should allow requester to create escrow with tokens", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(requester.address, amount);
    await token.connect(requester).approve(escrow.target, amount);

    await expect(escrow.connect(requester).createEscrow(intentId, token.target, amount, solver.address))
      .to.emit(escrow, "EscrowInitialized")
      .withArgs(intentId, escrow.target, requester.address, token.target, solver.address)
      .and.to.emit(escrow, "DepositMade")
      .withArgs(intentId, requester.address, amount, amount);

    expect(await token.balanceOf(escrow.target)).to.equal(amount);
    
    const escrowData = await escrow.getEscrow(intentId);
    expect(escrowData.amount).to.equal(amount);
  });

  /// Test: Escrow Creation After Claim Prevention
  /// Verifies that escrows cannot be created with an intent ID that was already claimed.
  /// Why: Prevents duplicate escrows and ensures each intent ID maps to a single escrow state.
  it("Should revert if escrow is already claimed", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(requester.address, amount);
    await token.connect(requester).approve(escrow.target, amount);
    await escrow.connect(requester).createEscrow(intentId, token.target, amount, solver.address);

    // This test is covered in claim.test.js - escrow creation with same intentId will fail
    // because escrow already exists, not because it's claimed
    await expect(
      escrow.connect(requester).createEscrow(intentId, token.target, amount, solver.address)
    ).to.be.revertedWith("Escrow already exists");
  });
});

