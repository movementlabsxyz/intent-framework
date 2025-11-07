const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentVaultTests, advanceTime } = require("./helpers/setup");

describe("IntentVault - Cancel", function () {
  let vault;
  let token;
  let verifierWallet;
  let maker;
  let solver;
  let intentId;
  let amount;

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
  });

  /// Test: Cancellation After Expiry
  /// Verifies that makers can cancel vaults after expiry and reclaim funds.
  it("Should allow maker to cancel and reclaim funds after expiry", async function () {
    // Cancellation blocked before expiry
    await expect(
      vault.connect(maker).cancel(intentId)
    ).to.be.revertedWithCustomError(vault, "VaultNotExpiredYet");

    // Advance time past expiry
    const expiryDuration = await vault.EXPIRY_DURATION();
    await advanceTime(Number(expiryDuration) + 1);
    
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

  /// Test: Unauthorized Cancellation Prevention
  /// Verifies that only the maker can cancel their vault.
  it("Should revert if not maker", async function () {
    await expect(
      vault.connect(solver).cancel(intentId)
    ).to.be.revertedWithCustomError(vault, "UnauthorizedMaker");
  });

  /// Test: Cancellation After Claim Prevention
  /// Verifies that attempting to cancel an already-claimed vault reverts.
  it("Should revert if already claimed", async function () {
    const approvalValue = 1;
    const messageHash = ethers.solidityPackedKeccak256(
      ["uint256", "uint8"],
      [intentId, approvalValue]
    );
    const signature = await verifierWallet.signMessage(ethers.getBytes(messageHash));
    
    await vault.connect(solver).claim(intentId, approvalValue, signature);

    await expect(
      vault.connect(maker).cancel(intentId)
    ).to.be.revertedWithCustomError(vault, "VaultAlreadyClaimed");
  });
});

