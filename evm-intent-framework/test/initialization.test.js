const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentEscrowTests } = require("./helpers/setup");

describe("IntentEscrow - Initialization", function () {
  let escrow;
  let token;
  let verifier;
  let maker;
  let intentId;

  beforeEach(async function () {
    const fixtures = await setupIntentEscrowTests();
    escrow = fixtures.escrow;
    token = fixtures.token;
    verifier = fixtures.verifier;
    maker = fixtures.maker;
    intentId = fixtures.intentId;
  });

  /// Test: Verifier Address Initialization
  /// Verifies that the escrow is deployed with the correct verifier address.
  it("Should initialize escrow with verifier address", async function () {
    expect(await escrow.verifier()).to.equal(verifier.address);
  });

  /// Test: Escrow Initialization
  /// Verifies that makers can initialize a new escrow and expiry is set correctly.
  it("Should allow maker to initialize an escrow", async function () {
    const tx = await escrow.connect(maker).initializeEscrow(intentId, token.target);
    const receipt = await tx.wait();
    const block = await ethers.provider.getBlock(receipt.blockNumber);
    
    await expect(tx)
      .to.emit(escrow, "EscrowInitialized")
      .withArgs(intentId, escrow.target, maker.address, token.target);

    const escrowData = await escrow.getEscrow(intentId);
    expect(escrowData.maker).to.equal(maker.address);
    expect(escrowData.token).to.equal(token.target);
    expect(escrowData.amount).to.equal(0);
    expect(escrowData.isClaimed).to.equal(false);
    
    // Verify expiry is set to block.timestamp + EXPIRY_DURATION
    const expectedExpiry = BigInt(block.timestamp) + BigInt(await escrow.EXPIRY_DURATION());
    expect(escrowData.expiry).to.equal(expectedExpiry);
  });

  /// Test: Duplicate Initialization Prevention
  /// Verifies that attempting to initialize an escrow with an existing intent ID reverts.
  it("Should revert if escrow already initialized", async function () {
    await escrow.connect(maker).initializeEscrow(intentId, token.target);
    
    await expect(
      escrow.connect(maker).initializeEscrow(intentId, token.target)
    ).to.be.revertedWith("Escrow already initialized");
  });
});

