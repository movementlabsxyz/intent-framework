const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentEscrowTests } = require("./helpers/setup");

describe("IntentEscrow - Claim", function () {
  let escrow;
  let token;
  let verifierWallet;
  let maker;
  let solver;
  let intentId;
  let amount;
  let approvalValue;

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
    await escrow.connect(maker).createEscrow(intentId, token.target, amount);
    
    approvalValue = 1; // Approval value must be 1
  });

  /// Test: Valid Claim with Verifier Signature
  /// Verifies that solvers can claim escrow funds when provided with a valid verifier signature.
  it("Should allow solver to claim with valid verifier signature", async function () {
    // Create message hash: keccak256(abi.encodePacked(intentId, approvalValue))
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256", "uint8"],
      [intentId, approvalValue]
    );
    
    // Sign message (signMessage automatically adds Ethereum signed message prefix)
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await expect(escrow.connect(solver).claim(intentId, approvalValue, signature))
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
  it("Should revert with invalid signature", async function () {
    const wrongIntentId = intentId + 1n;
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256", "uint8"],
      [wrongIntentId, approvalValue]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await expect(
      escrow.connect(solver).claim(intentId, approvalValue, signature)
    ).to.be.revertedWithCustomError(escrow, "UnauthorizedVerifier");
  });

  /// Test: Invalid Approval Value Rejection
  /// Verifies that claims with approval values other than 1 are rejected.
  it("Should revert with approval value != 1", async function () {
    const invalidApproval = 0;
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256", "uint8"],
      [intentId, invalidApproval]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await expect(
      escrow.connect(solver).claim(intentId, invalidApproval, signature)
    ).to.be.revertedWithCustomError(escrow, "InvalidApprovalValue");
  });

  /// Test: Duplicate Claim Prevention
  /// Verifies that attempting to claim an already-claimed escrow reverts.
  it("Should revert if escrow already claimed", async function () {
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256", "uint8"],
      [intentId, approvalValue]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await escrow.connect(solver).claim(intentId, approvalValue, signature);

    await expect(
      escrow.connect(solver).claim(intentId, approvalValue, signature)
    ).to.be.revertedWithCustomError(escrow, "EscrowAlreadyClaimed");
  });

  /// Test: Non-Existent Escrow Rejection
  /// Verifies that attempting to claim a non-existent escrow reverts with EscrowDoesNotExist error.
  it("Should revert if escrow does not exist", async function () {
    const newIntentId = intentId + 1n;

    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256", "uint8"],
      [newIntentId, approvalValue]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await expect(
      escrow.connect(solver).claim(newIntentId, approvalValue, signature)
    ).to.be.revertedWithCustomError(escrow, "EscrowDoesNotExist");
  });
});

