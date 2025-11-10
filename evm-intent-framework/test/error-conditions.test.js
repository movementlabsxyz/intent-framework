const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentEscrowTests } = require("./helpers/setup");

describe("IntentEscrow - Error Conditions", function () {
  let escrow;
  let token;
  let verifierWallet;
  let maker;
  let solver;
  let intentId;

  beforeEach(async function () {
    const fixtures = await setupIntentEscrowTests();
    escrow = fixtures.escrow;
    token = fixtures.token;
    verifierWallet = fixtures.verifierWallet;
    maker = fixtures.maker;
    solver = fixtures.solver;
    intentId = fixtures.intentId;
  });

  /// Test: Zero Amount Rejection
  /// Verifies that createEscrow reverts when amount is zero.
  it("Should revert with zero amount in createEscrow", async function () {
    await expect(
      escrow.connect(maker).createEscrow(intentId, token.target, 0, solver.address)
    ).to.be.revertedWith("Amount must be greater than 0");
  });

  /// Test: Insufficient Allowance Rejection
  /// Verifies that createEscrow reverts when ERC20 allowance is insufficient.
  /// Note: We mint tokens to ensure the maker has balance, then approve less than needed
  /// to test specifically the allowance check, not the balance check.
  it("Should revert with insufficient ERC20 allowance", async function () {
    const amount = ethers.parseEther("100");
    const insufficientAllowance = ethers.parseEther("50");
    
    // Mint tokens so maker has balance (required for transfer)
    await token.mint(maker.address, amount);
    // Approve less than amount to test allowance failure
    await token.connect(maker).approve(escrow.target, insufficientAllowance);

    await expect(
      escrow.connect(maker).createEscrow(intentId, token.target, amount, solver.address)
    ).to.be.reverted;
  });

  /// Test: Maximum Value Edge Case
  /// Verifies that createEscrow handles maximum uint256 values correctly.
  it("Should handle maximum uint256 value in createEscrow", async function () {
    const maxAmount = ethers.MaxUint256;
    
    // Mint maximum amount (this might fail in practice, but tests the contract logic)
    await token.mint(maker.address, maxAmount);
    await token.connect(maker).approve(escrow.target, maxAmount);

    // This should succeed if we have enough balance
    await expect(escrow.connect(maker).createEscrow(intentId, token.target, maxAmount, solver.address))
      .to.emit(escrow, "EscrowInitialized");
    
    const escrowData = await escrow.getEscrow(intentId);
    expect(escrowData.amount).to.equal(maxAmount);
  });

  /// Test: ETH Escrow Creation with address(0)
  /// Verifies that createEscrow accepts address(0) for ETH deposits.
  it("Should allow ETH escrow creation with address(0)", async function () {
    const amount = ethers.parseEther("1");
    
    await expect(
      escrow.connect(maker).createEscrow(intentId, ethers.ZeroAddress, amount, solver.address, { value: amount })
    ).to.emit(escrow, "EscrowInitialized")
      .withArgs(intentId, escrow.target, maker.address, ethers.ZeroAddress, solver.address);
    
    const escrowData = await escrow.getEscrow(intentId);
    expect(escrowData.token).to.equal(ethers.ZeroAddress);
    expect(escrowData.amount).to.equal(amount);
  });

  /// Test: ETH Amount Mismatch Rejection
  /// Verifies that createEscrow reverts when msg.value doesn't match amount for ETH deposits.
  it("Should revert with ETH amount mismatch", async function () {
    const amount = ethers.parseEther("1");
    const wrongValue = ethers.parseEther("0.5");

    await expect(
      escrow.connect(maker).createEscrow(intentId, ethers.ZeroAddress, amount, solver.address, { value: wrongValue })
    ).to.be.revertedWith("ETH amount mismatch");
  });

  /// Test: ETH Not Accepted for Token Escrow
  /// Verifies that createEscrow reverts when ETH is sent with a token address.
  it("Should revert when ETH sent with token address", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount);
    await token.connect(maker).approve(escrow.target, amount);

    await expect(
      escrow.connect(maker).createEscrow(intentId, token.target, amount, solver.address, { value: amount })
    ).to.be.revertedWith("ETH not accepted for token escrow");
  });

  /// Test: Invalid Signature Length Rejection
  /// Verifies that claim reverts with invalid signature length.
  it("Should revert with invalid signature length", async function () {
    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount);
    await token.connect(maker).approve(escrow.target, amount);
    await escrow.connect(maker).createEscrow(intentId, token.target, amount, solver.address);

    const approvalValue = 1;
    const invalidSignature = "0x1234"; // Too short (not 65 bytes)

    await expect(
      escrow.connect(solver).claim(intentId, approvalValue, invalidSignature)
    ).to.be.revertedWith("Invalid signature length");
  });

  /// Test: Non-Existent Escrow Cancellation Rejection
  /// Verifies that cancel reverts with EscrowDoesNotExist for non-existent escrows.
  it("Should revert cancel on non-existent escrow", async function () {
    const nonExistentIntentId = intentId + 1n;

    await expect(
      escrow.connect(maker).cancel(nonExistentIntentId)
    ).to.be.revertedWithCustomError(escrow, "EscrowDoesNotExist");
  });
});

