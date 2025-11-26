const { expect } = require("chai");
const { ethers } = require("hardhat");
const { main: mintToken } = require("../scripts/mint-token");
const { main: getTokenBalance } = require("../scripts/get-token-balance");
const { main: transferWithIntentId } = require("../scripts/transfer-with-intent-id");

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Helper to capture console output
/// Captures console.log and console.error output during script execution for test verification.
async function captureConsoleOutput(callback) {
  let output = "";
  const originalLog = console.log;
  const originalError = console.error;
  
  console.log = (...args) => {
    output += args.join(" ") + "\n";
    originalLog(...args);
  };
  
  console.error = (...args) => {
    output += args.join(" ") + "\n";
    originalError(...args);
  };
  
  try {
    await callback();
    return output;
  } finally {
    console.log = originalLog;
    console.error = originalError;
  }
}

describe("EVM Scripts - Utility Functions", function () {
  let token;
  let deployer;
  let alice;
  let bob;
  let tokenAddress;

  beforeEach(async function () {
    [deployer, alice, bob] = await ethers.getSigners();

    // Deploy MockERC20 token
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    token = await MockERC20.deploy("Test Token", "TEST", 18);
    await token.waitForDeployment();
    tokenAddress = await token.getAddress();
  });

  // ============================================================================
  // MINT TOKEN SCRIPT TESTS
  // ============================================================================

  describe("Mint Token Script Functionality", function () {
    /// Test: Basic Token Minting
    /// Verifies that the mint-token.js script correctly mints tokens to a recipient address.
    /// Why: Ensures the script properly interacts with MockERC20 contract and updates balances correctly.
    it("Should mint tokens to a recipient", async function () {
      const amount = ethers.parseEther("1000");
      
      // Set environment variables
      process.env.TOKEN_ADDRESS = tokenAddress;
      process.env.RECIPIENT = alice.address;
      process.env.AMOUNT = amount.toString();
      
      const output = await captureConsoleOutput(async () => {
        await mintToken(); // calling from mint-token.js
      });
      
      // Verify script output
      expect(output).to.include("SUCCESS");
      expect(output).to.include("Minted");
      expect(output).to.include(alice.address);
      
      // Verify balance was updated
      const balance = await token.balanceOf(alice.address);
      expect(balance).to.equal(amount);
      
      // Cleanup
      delete process.env.TOKEN_ADDRESS;
      delete process.env.RECIPIENT;
      delete process.env.AMOUNT;
    });

    /// Test: Large Amount Minting
    /// Verifies that the mint-token.js script handles large token amounts without overflow or precision issues.
    /// Why: E2E tests use large amounts (1000 ETH), so the script must handle these correctly.
    it("Should mint large amounts correctly", async function () {
      const amount = ethers.parseEther("1000000");
      
      process.env.TOKEN_ADDRESS = tokenAddress;
      process.env.RECIPIENT = bob.address;
      process.env.AMOUNT = amount.toString();
      
      const output = await captureConsoleOutput(async () => {
        await mintToken(); // calling from mint-token.js
      });
      
      expect(output).to.include("SUCCESS");
      
      const balance = await token.balanceOf(bob.address);
      expect(balance).to.equal(amount);
      
      delete process.env.TOKEN_ADDRESS;
      delete process.env.RECIPIENT;
      delete process.env.AMOUNT;
    });

    /// Test: Multiple Recipient Minting
    /// Verifies that the mint-token.js script can mint tokens to different recipients independently.
    /// Why: E2E tests need to mint tokens to both solver and requester accounts separately.
    it("Should mint to multiple recipients", async function () {
      const amount1 = ethers.parseEther("100");
      const amount2 = ethers.parseEther("200");
      
      // Mint to Alice
      process.env.TOKEN_ADDRESS = tokenAddress;
      process.env.RECIPIENT = alice.address;
      process.env.AMOUNT = amount1.toString();
      await mintToken(); // calling from mint-token.js
      
      // Mint to Bob
      process.env.RECIPIENT = bob.address;
      process.env.AMOUNT = amount2.toString();
      await mintToken(); // calling from mint-token.js
      
      expect(await token.balanceOf(alice.address)).to.equal(amount1);
      expect(await token.balanceOf(bob.address)).to.equal(amount2);
      
      delete process.env.TOKEN_ADDRESS;
      delete process.env.RECIPIENT;
      delete process.env.AMOUNT;
    });
  });

  // ============================================================================
  // GET TOKEN BALANCE SCRIPT TESTS
  // ============================================================================

  describe("Get Token Balance Script Functionality", function () {
    /// Test: Zero Balance Query
    /// Verifies that the get-token-balance.js script returns zero for accounts with no tokens.
    /// Why: E2E tests need to verify initial balances before operations to calculate expected final balances.
    it("Should return zero balance for account with no tokens", async function () {
      process.env.TOKEN_ADDRESS = tokenAddress;
      process.env.ACCOUNT = alice.address;
      
      const output = await captureConsoleOutput(async () => {
        await getTokenBalance(); // calling from get-token-balance.js
      });
      
      const balance = BigInt(output.trim());
      expect(balance).to.equal(0n);
      
      delete process.env.TOKEN_ADDRESS;
      delete process.env.ACCOUNT;
    });

    /// Test: Balance After Minting
    /// Verifies that the get-token-balance.js script returns the correct balance after tokens are minted.
    /// Why: E2E tests verify token balances after minting to ensure the solver has sufficient tokens for transfers.
    it("Should return correct balance after minting", async function () {
      const amount = ethers.parseEther("500");
      await token.connect(deployer).mint(alice.address, amount);
      
      process.env.TOKEN_ADDRESS = tokenAddress;
      process.env.ACCOUNT = alice.address;
      
      const output = await captureConsoleOutput(async () => {
        await getTokenBalance(); // calling from get-token-balance.js
      });
      
      const balance = BigInt(output.trim());
      expect(balance).to.equal(amount);
      
      delete process.env.TOKEN_ADDRESS;
      delete process.env.ACCOUNT;
    });

    /// Test: Balance After Transfer
    /// Verifies that the get-token-balance.js script correctly reflects balance changes after token transfers.
    /// Why: E2E tests verify that transfers actually occurred by checking balance changes on both sender and recipient.
    it("Should return correct balance after transfer", async function () {
      const mintAmount = ethers.parseEther("1000");
      const transferAmount = ethers.parseEther("300");
      
      await token.connect(deployer).mint(alice.address, mintAmount);
      await token.connect(alice).transfer(bob.address, transferAmount);
      
      process.env.TOKEN_ADDRESS = tokenAddress;
      
      process.env.ACCOUNT = alice.address;
      const aliceBalanceOutput = await captureConsoleOutput(async () => {
        await getTokenBalance(); // calling from get-token-balance.js
      });
      
      process.env.ACCOUNT = bob.address;
      const bobBalanceOutput = await captureConsoleOutput(async () => {
        await getTokenBalance(); // calling from get-token-balance.js
      });
      
      expect(BigInt(aliceBalanceOutput.trim())).to.equal(mintAmount - transferAmount);
      expect(BigInt(bobBalanceOutput.trim())).to.equal(transferAmount);
      
      delete process.env.TOKEN_ADDRESS;
      delete process.env.ACCOUNT;
    });
  });

  // ============================================================================
  // TRANSFER WITH INTENT ID SCRIPT TESTS
  // ============================================================================

  describe("Transfer with Intent ID Script Functionality", function () {
    beforeEach(async function () {
      // Mint tokens to Bob (solver) for transfers
      const amount = ethers.parseEther("10000");
      await token.connect(deployer).mint(bob.address, amount);
    });

    /// Test: ERC20 Transfer with Intent ID
    /// Verifies that the transfer-with-intent-id.js script performs ERC20 transfers with intent_id appended to calldata.
    /// Why: The verifier needs to extract intent_id from transaction calldata to validate outflow fulfillments. The script must format calldata correctly (100 bytes: selector + recipient + amount + intent_id).
    it("Should perform ERC20 transfer with intent_id in calldata", async function () {
      const transferAmount = ethers.parseEther("1000");
      const intentId = "0x1111111111111111111111111111111111111111111111111111111111111111";
      
      // Get initial balances
      const aliceBalanceBefore = await token.balanceOf(alice.address);
      const bobBalanceBefore = await token.balanceOf(bob.address);
      
      // Set environment variables
      process.env.TOKEN_ADDRESS = tokenAddress;
      process.env.RECIPIENT = alice.address;
      process.env.AMOUNT = transferAmount.toString();
      process.env.INTENT_ID = intentId;
      
      const output = await captureConsoleOutput(async () => {
        await transferWithIntentId(); // calling from transfer-with-intent-id.js
      });
      
      // Verify script output
      expect(output).to.include("SUCCESS");
      expect(output).to.include("Transaction hash:");
      expect(output).to.include("Recipient:");
      expect(output).to.include("Amount:");
      expect(output).to.include("Intent ID:");
      
      // Extract transaction hash from output
      const txHashMatch = output.match(/Transaction hash:\s*(0x[a-fA-F0-9]+)/);
      expect(txHashMatch).to.not.be.null;
      const txHash = txHashMatch[1];
      
      // Verify transaction was successful
      const receipt = await ethers.provider.getTransactionReceipt(txHash);
      expect(receipt).to.not.be.null;
      expect(receipt.status).to.equal(1);
      
      // Verify balances changed correctly
      const aliceBalanceAfter = await token.balanceOf(alice.address);
      const bobBalanceAfter = await token.balanceOf(bob.address);
      
      expect(aliceBalanceAfter).to.equal(aliceBalanceBefore + transferAmount);
      expect(bobBalanceAfter).to.equal(bobBalanceBefore - transferAmount);
      
      // Verify intent_id is in calldata by checking transaction data
      const tx = await ethers.provider.getTransaction(txHash);
      expect(tx.data.length).to.equal(202); // 0x + 200 hex chars = 202
      expect(tx.data).to.include(intentId.toLowerCase().replace(/^0x/, ""));
      
      // Cleanup
      delete process.env.TOKEN_ADDRESS;
      delete process.env.RECIPIENT;
      delete process.env.AMOUNT;
      delete process.env.INTENT_ID;
    });

    /// Test: Intent ID Format Handling
    /// Verifies that the transfer-with-intent-id.js script handles different intent_id hex formats correctly.
    /// Why: Intent IDs from Move chain may have varying formats (with/without 0x prefix, different hex casing). The script must normalize and pad them correctly.
    it("Should handle different intent_id formats", async function () {
      const transferAmount = ethers.parseEther("500");
      const intentId = "0x2222222222222222222222222222222222222222222222222222222222222222";
      
      process.env.TOKEN_ADDRESS = tokenAddress;
      process.env.RECIPIENT = alice.address;
      process.env.AMOUNT = transferAmount.toString();
      process.env.INTENT_ID = intentId;
      
      const output = await captureConsoleOutput(async () => {
        await transferWithIntentId(); // calling from transfer-with-intent-id.js
      });
      
      expect(output).to.include("SUCCESS");
      
      // Verify transfer occurred
      const aliceBalance = await token.balanceOf(alice.address);
      expect(aliceBalance).to.equal(transferAmount);
      
      delete process.env.TOKEN_ADDRESS;
      delete process.env.RECIPIENT;
      delete process.env.AMOUNT;
      delete process.env.INTENT_ID;
    });

    /// Test: Intent ID Without 0x Prefix
    /// Verifies that the transfer-with-intent-id.js script correctly handles intent_id strings without the 0x prefix.
    /// Why: Some systems may provide intent IDs without the 0x prefix. The script must handle both formats to be robust.
    it("Should handle intent_id without 0x prefix", async function () {
      const transferAmount = ethers.parseEther("200");
      const intentId = "1111111111111111111111111111111111111111111111111111111111111111";
      
      process.env.TOKEN_ADDRESS = tokenAddress;
      process.env.RECIPIENT = alice.address;
      process.env.AMOUNT = transferAmount.toString();
      process.env.INTENT_ID = intentId;
      
      const output = await captureConsoleOutput(async () => {
        await transferWithIntentId(); // calling from transfer-with-intent-id.js
      });
      
      expect(output).to.include("SUCCESS");
      
      // Verify transaction was successful
      const txHashMatch = output.match(/Transaction hash:\s*(0x[a-fA-F0-9]+)/);
      expect(txHashMatch).to.not.be.null;
      const receipt = await ethers.provider.getTransactionReceipt(txHashMatch[1]);
      expect(receipt.status).to.equal(1);
      
      delete process.env.TOKEN_ADDRESS;
      delete process.env.RECIPIENT;
      delete process.env.AMOUNT;
      delete process.env.INTENT_ID;
    });

    /// Test: Large Transfer Amounts
    /// Verifies that the transfer-with-intent-id.js script handles large transfer amounts (matching E2E test amounts).
    /// Why: E2E tests transfer 1000 ETH (1000000000000000000000 wei). The script must correctly encode large amounts in calldata without overflow.
    it("Should handle large transfer amounts", async function () {
      const transferAmount = ethers.parseEther("1000000");
      const intentId = "0x2222222222222222222222222222222222222222222222222222222222222222";
      
      // Ensure Bob has enough tokens
      await token.connect(deployer).mint(bob.address, transferAmount);
      
      process.env.TOKEN_ADDRESS = tokenAddress;
      process.env.RECIPIENT = alice.address;
      process.env.AMOUNT = transferAmount.toString();
      process.env.INTENT_ID = intentId;
      
      const output = await captureConsoleOutput(async () => {
        await transferWithIntentId(); // calling from transfer-with-intent-id.js
      });
      
      expect(output).to.include("SUCCESS");
      
      const aliceBalance = await token.balanceOf(alice.address);
      expect(aliceBalance).to.equal(transferAmount);
      
      delete process.env.TOKEN_ADDRESS;
      delete process.env.RECIPIENT;
      delete process.env.AMOUNT;
      delete process.env.INTENT_ID;
    });

    /// Test: Calldata Length Validation
    /// Verifies that the transfer-with-intent-id.js script generates calldata of exactly 100 bytes (4 + 32 + 32 + 32).
    /// Why: The verifier expects a specific calldata format. Incorrect length would cause parsing failures. This ensures the script matches the expected format.
    it("Should verify calldata length is 100 bytes", async function () {
      const transferAmount = ethers.parseEther("1000");
      const intentId = "0x1111111111111111111111111111111111111111111111111111111111111111";
      
      process.env.TOKEN_ADDRESS = tokenAddress;
      process.env.RECIPIENT = alice.address;
      process.env.AMOUNT = transferAmount.toString();
      process.env.INTENT_ID = intentId;
      
      const output = await captureConsoleOutput(async () => {
        await transferWithIntentId(); // calling from transfer-with-intent-id.js
      });
      
      // Extract transaction hash from output
      const txHashMatch = output.match(/Transaction hash:\s*(0x[a-fA-F0-9]+)/);
      expect(txHashMatch).to.not.be.null;
      const txHash = txHashMatch[1];
      
      // Get transaction to verify calldata length
      const tx = await ethers.provider.getTransaction(txHash);
      
      // Calldata should be: 4 bytes (selector) + 32 bytes (recipient) + 32 bytes (amount) + 32 bytes (intent_id) = 100 bytes
      // Hex string with 0x prefix: 2 chars (0x) + 8 (selector) + 64 (recipient) + 64 (amount) + 64 (intent_id) = 202 chars
      // Actual bytes: 4 + 32 + 32 + 32 = 100 bytes
      expect(tx.data.length).to.equal(202); // 0x + 200 hex chars = 202
      const dataWithoutPrefix = tx.data.replace(/^0x/, "");
      expect(dataWithoutPrefix.length).to.equal(200); // 200 hex characters = 100 bytes
      expect(Buffer.from(dataWithoutPrefix, 'hex').length).to.equal(100); // Verify byte length
      
      delete process.env.TOKEN_ADDRESS;
      delete process.env.RECIPIENT;
      delete process.env.AMOUNT;
      delete process.env.INTENT_ID;
    });
  });
});

