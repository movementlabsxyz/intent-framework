const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setupIntentVaultTests } = require("./helpers/setup");

describe("IntentVault - Initialization", function () {
  let vault;
  let token;
  let verifier;
  let maker;
  let intentId;

  beforeEach(async function () {
    const fixtures = await setupIntentVaultTests();
    vault = fixtures.vault;
    token = fixtures.token;
    verifier = fixtures.verifier;
    maker = fixtures.maker;
    intentId = fixtures.intentId;
  });

  /// Test: Verifier Address Initialization
  /// Verifies that the vault is deployed with the correct verifier address.
  it("Should initialize vault with verifier address", async function () {
    expect(await vault.verifier()).to.equal(verifier.address);
  });

  /// Test: Vault Initialization
  /// Verifies that makers can initialize a new vault and expiry is set correctly.
  it("Should allow maker to initialize a vault", async function () {
    const tx = await vault.connect(maker).initializeVault(intentId, token.target);
    const receipt = await tx.wait();
    const block = await ethers.provider.getBlock(receipt.blockNumber);
    
    await expect(tx)
      .to.emit(vault, "VaultInitialized")
      .withArgs(intentId, vault.target, maker.address, token.target);

    const vaultData = await vault.getVault(intentId);
    expect(vaultData.maker).to.equal(maker.address);
    expect(vaultData.token).to.equal(token.target);
    expect(vaultData.amount).to.equal(0);
    expect(vaultData.isClaimed).to.equal(false);
    
    // Verify expiry is set to block.timestamp + EXPIRY_DURATION
    const expectedExpiry = BigInt(block.timestamp) + BigInt(await vault.EXPIRY_DURATION());
    expect(vaultData.expiry).to.equal(expectedExpiry);
  });

  /// Test: Duplicate Initialization Prevention
  /// Verifies that attempting to initialize a vault with an existing intent ID reverts.
  it("Should revert if vault already initialized", async function () {
    await vault.connect(maker).initializeVault(intentId, token.target);
    
    await expect(
      vault.connect(maker).initializeVault(intentId, token.target)
    ).to.be.revertedWith("Vault already initialized");
  });
});

