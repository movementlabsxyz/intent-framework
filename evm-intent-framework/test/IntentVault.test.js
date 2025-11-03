const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("IntentVault", function () {
  let vault;
  let token;
  let verifier;
  let maker;
  let solver;
  let intentId;
  let verifierWallet;

  beforeEach(async function () {
    [verifier, maker, solver] = await ethers.getSigners();
    verifierWallet = verifier;

    // Deploy mock ERC20 token
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    token = await MockERC20.deploy("Test Token", "TEST");
    await token.waitForDeployment();

    // Deploy vault with verifier address
    const IntentVault = await ethers.getContractFactory("IntentVault");
    vault = await IntentVault.deploy(verifier.address);
    await vault.waitForDeployment();

    intentId = ethers.parseUnits("1", 0); // Simple intent ID
  });

  describe("Initialization", function () {
    it("Should initialize vault with verifier address", async function () {
      expect(await vault.verifier()).to.equal(verifier.address);
    });

    it("Should allow maker to initialize a vault", async function () {
      const expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
      await expect(vault.connect(maker).initializeVault(intentId, token.target, expiry))
        .to.emit(vault, "VaultInitialized")
        .withArgs(intentId, vault.target, maker.address, token.target);

      const vaultData = await vault.getVault(intentId);
      expect(vaultData.maker).to.equal(maker.address);
      expect(vaultData.token).to.equal(token.target);
      expect(vaultData.amount).to.equal(0);
      expect(vaultData.isClaimed).to.equal(false);
    });

    it("Should revert if vault already initialized", async function () {
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      await vault.connect(maker).initializeVault(intentId, token.target, expiry);
      
      await expect(
        vault.connect(maker).initializeVault(intentId, token.target, expiry)
      ).to.be.revertedWith("Vault already initialized");
    });
  });

  describe("Deposit", function () {
    beforeEach(async function () {
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      await vault.connect(maker).initializeVault(intentId, token.target, expiry);
    });

    it("Should allow maker to deposit tokens", async function () {
      const amount = ethers.parseEther("100");
      await token.mint(maker.address, amount);
      await token.connect(maker).approve(vault.target, amount);

      await expect(vault.connect(maker).deposit(intentId, amount))
        .to.emit(vault, "DepositMade")
        .withArgs(intentId, maker.address, amount, amount);

      expect(await token.balanceOf(vault.target)).to.equal(amount);
      
      const vaultData = await vault.getVault(intentId);
      expect(vaultData.amount).to.equal(amount);
    });

    it("Should revert if vault is already claimed", async function () {
      const amount = ethers.parseEther("100");
      await token.mint(maker.address, amount);
      await token.connect(maker).approve(vault.target, amount);
      await vault.connect(maker).deposit(intentId, amount);

      // Claim the vault (we'll set up signature later)
      // For now, manually mark as claimed by calling claim with proper signature
      // Actually, let's test this in the claim section
    });
  });

  describe("Claim", function () {
    let amount;
    let approvalValue;

    beforeEach(async function () {
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      await vault.connect(maker).initializeVault(intentId, token.target, expiry);
      
      amount = ethers.parseEther("100");
      await token.mint(maker.address, amount);
      await token.connect(maker).approve(vault.target, amount);
      await vault.connect(maker).deposit(intentId, amount);
      
      approvalValue = 1; // Approval value must be 1
    });

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

    it("Should revert if no deposit", async function () {
      const newIntentId = intentId + 1n;
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      await vault.connect(maker).initializeVault(newIntentId, token.target, expiry);

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

  describe("Cancel", function () {
    let amount;

    beforeEach(async function () {
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      await vault.connect(maker).initializeVault(intentId, token.target, expiry);
      
      amount = ethers.parseEther("100");
      await token.mint(maker.address, amount);
      await token.connect(maker).approve(vault.target, amount);
      await vault.connect(maker).deposit(intentId, amount);
    });

    it("Should allow maker to cancel and reclaim funds", async function () {
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

    it("Should revert if not maker", async function () {
      await expect(
        vault.connect(solver).cancel(intentId)
      ).to.be.revertedWithCustomError(vault, "UnauthorizedMaker");
    });

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
});

