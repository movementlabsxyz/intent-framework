const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentEscrowTests } = require("./helpers/setup");

describe("IntentEscrow - Claim", function () {
  let escrow;
  let token;
  let verifierWallet;
  let requester;
  let solver;
  let intentId;
  let amount;

  beforeEach(async function () {
    const fixtures = await setupIntentEscrowTests();
    escrow = fixtures.escrow;
    token = fixtures.token;
    verifierWallet = fixtures.verifierWallet;
    requester = fixtures.requester;
    solver = fixtures.solver;
    intentId = fixtures.intentId;

    amount = ethers.parseEther("100");
    await token.mint(requester.address, amount);
    await token.connect(requester).approve(escrow.target, amount);
    await escrow.connect(requester).createEscrow(intentId, token.target, amount, solver.address);
    
  });

  /// Test: Valid Claim with Verifier Signature
  /// Verifies that solvers can claim escrow funds when provided with a valid verifier signature.
  /// Why: Claiming is the core fulfillment mechanism. Solvers must be able to receive funds after verifier approval.
  it("Should allow solver to claim with valid verifier signature", async function () {
    // Create message hash: keccak256(intentId) - signature itself is the approval
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256"],
      [intentId]
    );
    
    // Sign message (signMessage automatically adds Ethereum signed message prefix)
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await expect(escrow.connect(solver).claim(intentId, signature))
      .to.emit(escrow, "EscrowClaimed")
      .withArgs(intentId, solver.address, amount);

    expect(await token.balanceOf(solver.address)).to.equal(amount);
    expect(await token.balanceOf(escrow.target)).to.equal(0);
    
    const escrowData = await escrow.getEscrow(intentId);
    expect(escrowData.isClaimed).to.equal(true);
    expect(escrowData.amount).to.equal(0);
  });

  /// Test: Invalid Signature Rejection
  /// Verifies that claims with invalid signatures are rejected with UnauthorizedVerifier error.
  /// Why: Security requirement - only verifier-approved fulfillments should allow fund release.
  it("Should revert with invalid signature", async function () {
    const wrongIntentId = intentId + 1n;
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256"],
      [wrongIntentId]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await expect(
      escrow.connect(solver).claim(intentId, signature)
    ).to.be.revertedWithCustomError(escrow, "UnauthorizedVerifier");
  });

  /// Test: Signature Replay Prevention
  /// Verifies that a signature for one intent_id cannot be reused on a different escrow with a different intent_id.
  /// Why: Signatures must be bound to specific intent_ids to prevent replay attacks across different escrows.
  it("Should prevent signature replay across different intent_ids", async function () {
    // Create a second escrow with a different intent_id
    const intentIdB = intentId + 1n;
    const amountB = ethers.parseEther("50");
    await token.mint(requester.address, amountB);
    await token.connect(requester).approve(escrow.target, amountB);
    await escrow.connect(requester).createEscrow(intentIdB, token.target, amountB, solver.address);

    // Create a VALID signature for intent_id A (the first escrow)
    const messageHashA = ethers.solidityPackedKeccak256(
      ["uint256"],
      [intentId]
    );
    const signatureForA = await verifierWallet.signMessage(ethers.getBytes(messageHashA));

    // Try to use the signature for intent_id A on escrow B (which has intent_id B)
    // This should fail because the signature is bound to intent_id A, not intent_id B
    await expect(
      escrow.connect(solver).claim(intentIdB, signatureForA)
    ).to.be.revertedWithCustomError(escrow, "UnauthorizedVerifier");
  });



  /// Test: Duplicate Claim Prevention
  /// Verifies that attempting to claim an already-claimed escrow reverts.
  /// Why: Prevents double-spending - each escrow can only be claimed once.
  it("Should revert if escrow already claimed", async function () {
    // Signature is over intentId only (signature itself is the approval)
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256"],
      [intentId]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await escrow.connect(solver).claim(intentId, signature);

    await expect(
      escrow.connect(solver).claim(intentId, signature)
    ).to.be.revertedWithCustomError(escrow, "EscrowAlreadyClaimed");
  });

  /// Test: Non-Existent Escrow Rejection
  /// Verifies that attempting to claim a non-existent escrow reverts with EscrowDoesNotExist error.
  /// Why: Prevents claims on non-existent escrows and ensures proper error handling.
  it("Should revert if escrow does not exist", async function () {
    const newIntentId = intentId + 1n;

    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256"],
      [newIntentId]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await expect(
      escrow.connect(solver).claim(newIntentId, signature)
    ).to.be.revertedWithCustomError(escrow, "EscrowDoesNotExist");
  });
});

