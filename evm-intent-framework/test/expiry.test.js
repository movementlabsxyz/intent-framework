const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentVaultTests, advanceTime } = require("./helpers/setup");

describe("IntentVault - Expiry Handling", function () {
  let vault;
  let token;
  let verifierWallet;
  let maker;
  let solver;
  let intentId;

  beforeEach(async function () {
    const fixtures = await setupIntentVaultTests();
    vault = fixtures.vault;
    token = fixtures.token;
    verifierWallet = fixtures.verifierWallet;
    maker = fixtures.maker;
    solver = fixtures.solver;
    intentId = fixtures.intentId;
  });

  /// Test: Expired Vault Cancellation
  /// Verifies that makers can cancel vaults after expiry and reclaim funds.
  /// Cancellation before expiry is blocked to ensure funds remain locked until expiry.
  it("Should allow maker to cancel expired vault", async function () {
    await vault.connect(maker).initializeVault(intentId, token.target);
    
    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount);
    await token.connect(maker).approve(vault.target, amount);
    await vault.connect(maker).deposit(intentId, amount);

    // Cancellation blocked before expiry
    await expect(
      vault.connect(maker).cancel(intentId)
    ).to.be.revertedWithCustomError(vault, "VaultNotExpiredYet");

    // Advance time past expiry
    const expiryDuration = await vault.EXPIRY_DURATION();
    await advanceTime(Number(expiryDuration) + 1);

    // Cancellation allowed after expiry
    const initialBalance = await token.balanceOf(maker.address);
    await expect(vault.connect(maker).cancel(intentId))
      .to.emit(vault, "VaultCancelled")
      .withArgs(intentId, maker.address, amount);

    expect(await token.balanceOf(maker.address)).to.equal(initialBalance + amount);
    expect(await token.balanceOf(vault.target)).to.equal(0);
    
    const vaultData = await vault.getVault(intentId);
    expect(vaultData.isClaimed).to.equal(true);
    expect(vaultData.amount).to.equal(0);
  });

  /// Test: Expiry Timestamp Validation
  /// Verifies that expiry timestamp is correctly calculated and stored.
  it("Should verify expiry timestamp is stored correctly", async function () {
    const tx = await vault.connect(maker).initializeVault(intentId, token.target);
    const receipt = await tx.wait();
    const block = await ethers.provider.getBlock(receipt.blockNumber);

    const vaultData = await vault.getVault(intentId);
    const expiryDuration = await vault.EXPIRY_DURATION();
    const expectedExpiry = BigInt(block.timestamp) + BigInt(expiryDuration);
    expect(vaultData.expiry).to.equal(expectedExpiry);
    
    expect(vaultData.maker).to.equal(maker.address);
    expect(vaultData.token).to.equal(token.target);
    expect(vaultData.amount).to.equal(0);
    expect(vaultData.isClaimed).to.equal(false);
  });

  /// Test: Expired Vault Claim Prevention
  /// Verifies that expired vaults cannot be claimed, even with valid verifier signatures.
  it("Should prevent claim on expired vault", async function () {
    await vault.connect(maker).initializeVault(intentId, token.target);
    
    const amount = ethers.parseEther("100");
    await token.mint(maker.address, amount);
    await token.connect(maker).approve(vault.target, amount);
    await vault.connect(maker).deposit(intentId, amount);

    // Advance time past expiry
    const expiryDuration = await vault.EXPIRY_DURATION();
    await advanceTime(Number(expiryDuration) + 1);

    // Claims blocked after expiry
    const approvalValue = 1;
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256", "uint8"],
      [intentId, approvalValue]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));

    await expect(
      vault.connect(solver).claim(intentId, approvalValue, signature)
    ).to.be.revertedWithCustomError(vault, "VaultExpired");

    expect(await token.balanceOf(vault.target)).to.equal(amount);
    expect(await token.balanceOf(solver.address)).to.equal(0);
    
    const vaultData = await vault.getVault(intentId);
    expect(vaultData.isClaimed).to.equal(false);
    expect(vaultData.amount).to.equal(amount);
  });
});

