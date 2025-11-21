const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentEscrowTests, advanceTime } = require("./helpers/setup");

describe("IntentEscrow - Cancel", function () {
  let escrow;
  let token;
  let verifierWallet;
  let maker;
  let solver;
  let intentId;
  let amount;

  beforeEach(async function () {
    const fixtures = await setupIntentEscrowTests();
    escrow = fixtures.escrow;
    token = fixtures.token;
    verifierWallet = fixtures.verifierWallet;
    maker = fixtures.maker;
    solver = fixtures.solver;
    intentId = fixtures.intentId;
    
    amount = ethers.parseEther("100");
    await token.mint(maker.address, amount);
    await token.connect(maker).approve(escrow.target, amount);
    await escrow.connect(maker).createEscrow(intentId, token.target, amount, solver.address);
  });

  /// Test: Cancellation After Expiry
  /// Verifies that makers can cancel escrows after expiry and reclaim funds.
  /// Why: Makers need a way to reclaim funds if fulfillment doesn't occur before expiry.
  it("Should allow maker to cancel and reclaim funds after expiry", async function () {
    // Cancellation blocked before expiry
    await expect(
      escrow.connect(maker).cancel(intentId)
    ).to.be.revertedWithCustomError(escrow, "EscrowNotExpiredYet");

    // Advance time past expiry
    const expiryDuration = await escrow.EXPIRY_DURATION();
    await advanceTime(Number(expiryDuration) + 1);
    
    const initialBalance = await token.balanceOf(maker.address);
    
    await expect(escrow.connect(maker).cancel(intentId))
      .to.emit(escrow, "EscrowCancelled")
      .withArgs(intentId, maker.address, amount);

    expect(await token.balanceOf(maker.address)).to.equal(initialBalance + amount);
    expect(await token.balanceOf(escrow.target)).to.equal(0);
    
    const escrowData = await escrow.getEscrow(intentId);
    expect(escrowData.isClaimed).to.equal(true);
    expect(escrowData.amount).to.equal(0);
  });

  /// Test: Unauthorized Cancellation Prevention
  /// Verifies that only the maker can cancel their escrow.
  /// Why: Security requirement - only the escrow creator should be able to cancel.
  it("Should revert if not maker", async function () {
    await expect(
      escrow.connect(solver).cancel(intentId)
    ).to.be.revertedWithCustomError(escrow, "UnauthorizedMaker");
  });

  /// Test: Cancellation After Claim Prevention
  /// Verifies that attempting to cancel an already-claimed escrow reverts.
  /// Why: Once funds are claimed, they cannot be cancelled to prevent double-spending.
  it("Should revert if already claimed", async function () {
    // Signature is over intentId only (signature itself is the approval)
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256"],
      [intentId]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));
    
    await escrow.connect(solver).claim(intentId, signature);

    await expect(
      escrow.connect(maker).cancel(intentId)
    ).to.be.revertedWithCustomError(escrow, "EscrowAlreadyClaimed");
  });
});

