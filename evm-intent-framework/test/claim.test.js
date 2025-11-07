const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentVaultTests } = require("./helpers/setup");

describe("IntentVault - Claim", function () {
  let vault;
  let token;
  let verifierWallet;
  let maker;
  let solver;
  let intentId;
  let amount;
  let approvalValue;

  beforeEach(async function () {
    const fixtures = await setupIntentVaultTests();
    vault = fixtures.vault;
    token = fixtures.token;
    verifierWallet = fixtures.verifierWallet;
    maker = fixtures.maker;
    solver = fixtures.solver;
    intentId = fixtures.intentId;

    await vault.connect(maker).initializeVault(intentId, token.target);
    
    amount = ethers.parseEther("100");
    await token.mint(maker.address, amount);
    await token.connect(maker).approve(vault.target, amount);
    await vault.connect(maker).deposit(intentId, amount);
    
    approvalValue = 1; // Approval value must be 1
  });

  /// Test: Valid Claim with Verifier Signature
  /// Verifies that solvers can claim vault funds when provided with a valid verifier signature.
  it("Should allow solver to claim with valid verifier signature", async function () {
    // Create message hash: keccak256(abi.encodePacked(intentId, approvalValue))
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256", "uint8"],
      [intentId, approvalValue]
    );
    
    // Sign message (signMessage automatically adds Ethereum signed message prefix)
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await expect(vault.connect(solver).claim(intentId, approvalValue, signature))
      .to.emit(vault, "VaultClaimed")
      .withArgs(intentId, solver.address, amount);

    expect(await token.balanceOf(solver.address)).to.equal(amount);
    expect(await token.balanceOf(vault.target)).to.equal(0);
    
    const vaultData = await vault.getVault(intentId);
    expect(vaultData.isClaimed).to.equal(true);
    expect(vaultData.amount).to.equal(0);
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
      vault.connect(solver).claim(intentId, approvalValue, signature)
    ).to.be.revertedWithCustomError(vault, "UnauthorizedVerifier");
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
      vault.connect(solver).claim(intentId, invalidApproval, signature)
    ).to.be.revertedWithCustomError(vault, "InvalidApprovalValue");
  });

  /// Test: Duplicate Claim Prevention
  /// Verifies that attempting to claim an already-claimed vault reverts.
  it("Should revert if vault already claimed", async function () {
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256", "uint8"],
      [intentId, approvalValue]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await vault.connect(solver).claim(intentId, approvalValue, signature);

    await expect(
      vault.connect(solver).claim(intentId, approvalValue, signature)
    ).to.be.revertedWithCustomError(vault, "VaultAlreadyClaimed");
  });

  /// Test: No Deposit Rejection
  /// Verifies that attempting to claim a vault with no deposits reverts with NoDeposit error.
  it("Should revert if no deposit", async function () {
    const newIntentId = intentId + 1n;
    await vault.connect(maker).initializeVault(newIntentId, token.target);

    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256", "uint8"],
      [newIntentId, approvalValue]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await expect(
      vault.connect(solver).claim(newIntentId, approvalValue, signature)
    ).to.be.revertedWithCustomError(vault, "NoDeposit");
  });
});

