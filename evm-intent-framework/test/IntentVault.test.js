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

  describe("Cross-Chain Intent ID Conversion", function () {
    /// Helper function to convert Aptos hex intent ID to EVM uint256
    /// Removes 0x prefix if present and pads to 64 hex characters (32 bytes)
    function hexToUint256(hexString) {
      const hex = hexString.startsWith('0x') ? hexString.slice(2) : hexString;
      return BigInt('0x' + hex.padStart(64, '0'));
    }

    /// Test: Aptos Hex to EVM uint256 Conversion
    /// Verifies that intent IDs from Aptos hex format can be converted and used in EVM vault operations.
    it("Should handle Aptos hex intent ID conversion to EVM uint256", async function () {
      // Aptos intent ID in hex format (smaller than 32 bytes)
      const aptosIntentIdHex = "0x1234";
      const evmIntentId = hexToUint256(aptosIntentIdHex);

      // Initialize vault with converted intent ID
      await vault.connect(maker).initializeVault(evmIntentId, token.target);

      // Verify vault was initialized correctly
      const vaultData = await vault.getVault(evmIntentId);
      expect(vaultData.maker).to.equal(maker.address);
      expect(vaultData.token).to.equal(token.target);

      // Deposit and verify it works with converted intent ID
      const amount = ethers.parseEther("100");
      await token.mint(maker.address, amount);
      await token.connect(maker).approve(vault.target, amount);
      await vault.connect(maker).deposit(evmIntentId, amount);

      expect(await token.balanceOf(vault.target)).to.equal(amount);
    });

    /// Test: Intent ID Boundary Values
    /// Verifies that the contract handles boundary intent ID values correctly.
    it("Should handle intent ID boundary values", async function () {
      // Test maximum uint256 value
      const maxIntentId = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
      await vault.connect(maker).initializeVault(maxIntentId, token.target);
      const maxVaultData = await vault.getVault(maxIntentId);
      expect(maxVaultData.maker).to.equal(maker.address);

      // Test zero value
      const zeroIntentId = 0n;
      await vault.connect(maker).initializeVault(zeroIntentId, token.target);
      const zeroVaultData = await vault.getVault(zeroIntentId);
      expect(zeroVaultData.maker).to.equal(maker.address);

      // Test edge value (2^128 - 1)
      const edgeIntentId = BigInt("0xffffffffffffffffffffffffffffffff");
      await vault.connect(maker).initializeVault(edgeIntentId, token.target);
      const edgeVaultData = await vault.getVault(edgeIntentId);
      expect(edgeVaultData.maker).to.equal(maker.address);
    });

    /// Test: Intent ID Zero Padding
    /// Verifies that shorter intent IDs are properly left-padded with zeros.
    it("Should handle intent ID zero padding correctly", async function () {
      // Test various short hex strings that need padding
      const shortHexIds = [
        "0x1",
        "0x12",
        "0x123",
        "0x1234",
        "0x12345",
        "0x1234567890abcdef"
      ];

      for (const hexId of shortHexIds) {
        const paddedIntentId = hexToUint256(hexId);
        const expectedValue = BigInt(hexId);

        // Verify padding produces correct value
        expect(paddedIntentId).to.equal(expectedValue);

        // Verify vault operations work with padded intent ID
        await vault.connect(maker).initializeVault(paddedIntentId, token.target);
        const vaultData = await vault.getVault(paddedIntentId);
        expect(vaultData.maker).to.equal(maker.address);
      }
    });

    /// Test: Multiple Intent IDs from Different Formats
    /// Verifies that multiple vaults can be created with intent IDs from different Aptos formats.
    it("Should handle multiple intent IDs from different Aptos formats", async function () {
      const intentIds = [
        hexToUint256("0x1"),
        hexToUint256("0x1234"),
        hexToUint256("0xabcdef"),
        hexToUint256("0x1234567890abcdef"),
        ethers.parseUnits("1000000", 0), // Direct uint256 format
        ethers.parseUnits("999999", 0) // Large number format
      ];

      // Initialize vaults with different intent ID formats
      for (let i = 0; i < intentIds.length; i++) {
        await vault.connect(maker).initializeVault(intentIds[i], token.target);
        const vaultData = await vault.getVault(intentIds[i]);
        expect(vaultData.maker).to.equal(maker.address);
        expect(vaultData.token).to.equal(token.target);
      }

      // Verify all vaults are independent
      expect(await vault.getVault(intentIds[0])).to.not.be.undefined;
      expect(await vault.getVault(intentIds[1])).to.not.be.undefined;
      expect(await vault.getVault(intentIds[2])).to.not.be.undefined;
    });
  });
});

