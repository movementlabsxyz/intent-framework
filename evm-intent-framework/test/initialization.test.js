const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentEscrowTests } = require("./helpers/setup");

describe("IntentEscrow - Initialization", function () {
  let escrow;
  let token;
  let verifier;
  let maker;
  let solver;
  let intentId;

  beforeEach(async function () {
    const fixtures = await setupIntentEscrowTests();
    escrow = fixtures.escrow;
    token = fixtures.token;
    verifier = fixtures.verifier;
    maker = fixtures.maker;
    solver = fixtures.solver;
    intentId = fixtures.intentId;
  });

  /// Test: Verifier Address Initialization
  /// Verifies that the escrow is deployed with the correct verifier address.
  /// Why: The verifier address is critical for signature validation. Incorrect initialization would break security.
  it("Should initialize escrow with verifier address", async function () {
    expect(await escrow.verifier()).to.equal(verifier.address);
  });

  /// Test: Escrow Creation
  /// Verifies that makers can create a new escrow with funds atomically and expiry is set correctly.
  /// Why: Escrow creation must be atomic and set expiry correctly to enable time-based cancellation.
  it("Should allow maker to create an escrow", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount);
    await token.connect(maker).approve(escrow.target, amount);
    
    const tx = await escrow.connect(maker).createEscrow(intentId, token.target, amount, solver.address);
    const receipt = await tx.wait();
    const block = await ethers.provider.getBlock(receipt.blockNumber);
    
    await expect(tx)
      .to.emit(escrow, "EscrowInitialized")
      .withArgs(intentId, escrow.target, maker.address, token.target, solver.address);
    
    await expect(tx)
      .to.emit(escrow, "DepositMade")
      .withArgs(intentId, maker.address, amount, amount);

    const escrowData = await escrow.getEscrow(intentId);
    expect(escrowData.maker).to.equal(maker.address);
    expect(escrowData.token).to.equal(token.target);
    expect(escrowData.amount).to.equal(amount);
    expect(escrowData.isClaimed).to.equal(false);
    
    // Verify expiry is set to block.timestamp + EXPIRY_DURATION
    const expectedExpiry = BigInt(block.timestamp) + BigInt(await escrow.EXPIRY_DURATION());
    expect(escrowData.expiry).to.equal(expectedExpiry);
  });

  /// Test: Duplicate Creation Prevention
  /// Verifies that attempting to create an escrow with an existing intent ID reverts.
  /// Why: Each intent ID must map to a single escrow to maintain state consistency.
  it("Should revert if escrow already exists", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount);
    await token.connect(maker).approve(escrow.target, amount);
    await escrow.connect(maker).createEscrow(intentId, token.target, amount, solver.address);
    
    await expect(
      escrow.connect(maker).createEscrow(intentId, token.target, amount, solver.address)
    ).to.be.revertedWith("Escrow already exists");
  });
});

