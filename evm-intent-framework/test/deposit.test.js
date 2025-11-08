const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentEscrowTests } = require("./helpers/setup");

describe("IntentEscrow - Create Escrow (Deposit)", function () {
  let escrow;
  let token;
  let maker;
  let intentId;

  beforeEach(async function () {
    const fixtures = await setupIntentEscrowTests();
    escrow = fixtures.escrow;
    token = fixtures.token;
    maker = fixtures.maker;
    intentId = fixtures.intentId;
  });

  /// Test: Token Escrow Creation
  /// Verifies that makers can create an escrow with ERC20 tokens atomically.
  it("Should allow maker to create escrow with tokens", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount);
    await token.connect(maker).approve(escrow.target, amount);

    await expect(escrow.connect(maker).createEscrow(intentId, token.target, amount))
      .to.emit(escrow, "EscrowInitialized")
      .withArgs(intentId, escrow.target, maker.address, token.target)
      .and.to.emit(escrow, "DepositMade")
      .withArgs(intentId, maker.address, amount, amount);

    expect(await token.balanceOf(escrow.target)).to.equal(amount);
    
    const escrowData = await escrow.getEscrow(intentId);
    expect(escrowData.amount).to.equal(amount);
  });

  /// Test: Escrow Creation After Claim Prevention
  /// Verifies that escrows cannot be created with an intent ID that was already claimed.
  it("Should revert if escrow is already claimed", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount);
    await token.connect(maker).approve(escrow.target, amount);
    await escrow.connect(maker).createEscrow(intentId, token.target, amount);

    // This test is covered in claim.test.js - escrow creation with same intentId will fail
    // because escrow already exists, not because it's claimed
    await expect(
      escrow.connect(maker).createEscrow(intentId, token.target, amount)
    ).to.be.revertedWith("Escrow already exists");
  });
});

