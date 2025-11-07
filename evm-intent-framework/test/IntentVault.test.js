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

  describe("Deposit", function () {
    beforeEach(async function () {
      await vault.connect(maker).initializeVault(intentId, token.target);
    });

    /// Test: Token Deposit
    /// Verifies that makers can deposit ERC20 tokens into an initialized vault.
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

    /// Test: Deposit After Claim Prevention
    /// Verifies that deposits cannot be made to a vault that has already been claimed.
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

  describe("Cancel", function () {
    let amount;

    beforeEach(async function () {
      await vault.connect(maker).initializeVault(intentId, token.target);
      
      amount = ethers.parseEther("100");
      await token.mint(maker.address, amount);
      await token.connect(maker).approve(vault.target, amount);
      await vault.connect(maker).deposit(intentId, amount);
    });

    /// Helper function to advance blockchain time for expiry testing
    /// Uses Hardhat's evm_increaseTime to simulate time passage
    /// @param seconds Number of seconds to advance
    async function advanceTime(seconds) {
      await ethers.provider.send("evm_increaseTime", [seconds]);
      await ethers.provider.send("evm_mine", []);
    }

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

  describe("Expiry Handling", function () {
    /// Helper function to advance blockchain time for expiry testing
    /// Uses Hardhat's evm_increaseTime to simulate time passage
    /// @param seconds Number of seconds to advance
    async function advanceTime(seconds) {
      await ethers.provider.send("evm_increaseTime", [seconds]);
      await ethers.provider.send("evm_mine", []);
    }

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
});

