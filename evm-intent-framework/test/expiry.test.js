const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentEscrowTests, advanceTime } = require("./helpers/setup");

describe("IntentEscrow - Expiry Handling", function () {
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

  /// Test: Expired Escrow Cancellation
  /// Verifies that requesters can cancel escrows after expiry and reclaim funds.
  /// Why: Requesters need a way to reclaim funds if fulfillment doesn't occur before expiry. Cancellation before expiry is blocked to ensure funds remain locked until expiry.
  it("Should allow requester to cancel expired escrow", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(requester.address, amount);
    await token.connect(requester).approve(escrow.target, amount);
    await escrow.connect(requester).createEscrow(intentId, token.target, amount, solver.address);

    // Cancellation blocked before expiry
    await expect(
      escrow.connect(requester).cancel(intentId)
    ).to.be.revertedWithCustomError(escrow, "EscrowNotExpiredYet");

    // Advance time past expiry
    const expiryDuration = await escrow.EXPIRY_DURATION();
    await advanceTime(Number(expiryDuration) + 1);

    // Cancellation allowed after expiry
    const initialBalance = await token.balanceOf(requester.address);
    await expect(escrow.connect(requester).cancel(intentId))
      .to.emit(escrow, "EscrowCancelled")
      .withArgs(intentId, requester.address, amount);

    expect(await token.balanceOf(requester.address)).to.equal(initialBalance + amount);
    expect(await token.balanceOf(escrow.target)).to.equal(0);
    
    const escrowData = await escrow.getEscrow(intentId);
    expect(escrowData.isClaimed).to.equal(true);
    expect(escrowData.amount).to.equal(0);
  });

  /// Test: Expiry Timestamp Validation
  /// Verifies that expiry timestamp is correctly calculated and stored.
  /// Why: Correct expiry calculation is critical for time-based cancellation logic.
  it("Should verify expiry timestamp is stored correctly", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(requester.address, amount);
    await token.connect(requester).approve(escrow.target, amount);
    const tx = await escrow.connect(requester).createEscrow(intentId, token.target, amount, solver.address);
    const receipt = await tx.wait();
    const block = await ethers.provider.getBlock(receipt.blockNumber);

    const escrowData = await escrow.getEscrow(intentId);
    const expiryDuration = await escrow.EXPIRY_DURATION();
    const expectedExpiry = BigInt(block.timestamp) + BigInt(expiryDuration);
    expect(escrowData.expiry).to.equal(expectedExpiry);
    
    expect(escrowData.requester).to.equal(requester.address);
    expect(escrowData.token).to.equal(token.target);
    expect(escrowData.amount).to.equal(amount);
    expect(escrowData.isClaimed).to.equal(false);
  });

  /// Test: Expired Escrow Claim Prevention
  /// Verifies that expired escrows cannot be claimed, even with valid verifier signatures.
  /// Why: Expired escrows should only be cancellable by the requester, not claimable by solvers.
  it("Should prevent claim on expired escrow", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(requester.address, amount);
    await token.connect(requester).approve(escrow.target, amount);
    await escrow.connect(requester).createEscrow(intentId, token.target, amount, solver.address);

    // Advance time past expiry
    const expiryDuration = await escrow.EXPIRY_DURATION();
    await advanceTime(Number(expiryDuration) + 1);

    // Claims blocked after expiry
    // Signature is over intentId only (signature itself is the approval)
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256"],
      [intentId]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await expect(
      escrow.connect(solver).claim(intentId, signature)
    ).to.be.revertedWithCustomError(escrow, "EscrowExpired");

    expect(await token.balanceOf(escrow.target)).to.equal(amount);
    expect(await token.balanceOf(solver.address)).to.equal(0);
    
    const escrowData = await escrow.getEscrow(intentId);
    expect(escrowData.isClaimed).to.equal(false);
    expect(escrowData.amount).to.equal(amount);
  });
});

