//! ERC20 transfer with intent_id metadata
//!
//! This script executes an ERC20 transfer() call with intent_id appended in calldata.
//! The calldata format is: selector (4 bytes) + recipient (32 bytes) + amount (32 bytes) + intent_id (32 bytes).
//! The ERC20 contract ignores the extra intent_id bytes, but they remain in the transaction
//! data for verifier tracking.

const hre = require("hardhat");

/// Executes ERC20 transfer with intent_id in calldata
///
/// # Environment Variables
/// - `TOKEN_ADDRESS`: ERC20 token contract address
/// - `RECIPIENT`: Recipient address (20 bytes, EVM format)
/// - `AMOUNT`: Transfer amount in base units (wei for 18 decimals)
/// - `INTENT_ID`: Intent ID to append in calldata (32 bytes, hex format with 0x prefix)
///
/// # Returns
/// Outputs transaction hash, recipient, amount, and intent_id on success.
async function main() {
  const tokenAddress = process.env.TOKEN_ADDRESS;
  const recipient = process.env.RECIPIENT;
  const amount = process.env.AMOUNT;
  const intentId = process.env.INTENT_ID;

  if (!tokenAddress || !recipient || !amount || !intentId) {
    const error = new Error("Missing required environment variables: TOKEN_ADDRESS, RECIPIENT, AMOUNT, INTENT_ID");
    console.error("Error:", error.message);
    if (require.main === module) {
      process.exit(1);
    }
    throw error;
  }

  // Get solver signer
  // For in-memory Hardhat network (unit tests): use hre.ethers.getSigners()
  // For external networks (E2E tests): use raw ethers to avoid HardhatEthersProvider.resolveName bug
  let solver;
  
  if (hre.network.name === "hardhat") {
    // In-memory Hardhat network (unit tests) - getSigners() works fine here
    const signers = await hre.ethers.getSigners();
    if (signers.length < 3) {
      throw new Error(`Expected at least 3 signers, got ${signers.length}`);
    }
    solver = signers[2];
  } else if (process.env.BASE_SOLVER_PRIVATE_KEY) {
    // Testnet: Create wallet from private key using raw ethers
    const { ethers } = require("ethers");
    const rpcUrl = hre.network.config.url || "http://127.0.0.1:8545";
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    solver = new ethers.Wallet(process.env.BASE_SOLVER_PRIVATE_KEY, provider);
  } else {
    // External network (E2E tests): use raw ethers to avoid resolveName bug
    const { ethers } = require("ethers");
    const rpcUrl = hre.network.config.url || "http://127.0.0.1:8545";
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const accounts = await provider.send("eth_accounts", []);
    if (accounts.length < 3) {
      throw new Error(`Expected at least 3 accounts from Hardhat node, got ${accounts.length}`);
    }
    solver = await provider.getSigner(accounts[2]);
  }

  const amountBigInt = BigInt(amount);
  const selector = "0xa9059cbb";
  
  const recipientClean = recipient.toLowerCase().replace(/^0x/, "");
  const intentIdClean = intentId.toLowerCase().replace(/^0x/, "");
  const recipientPadded = "0".repeat(24) + recipientClean;
  
  const amountHex = amountBigInt.toString(16);
  const amountPadded = "0".repeat(64 - amountHex.length) + amountHex;
  const intentIdPadded = intentIdClean.padStart(64, "0");
  
  const data = selector + recipientPadded + amountPadded + intentIdPadded;

  // Extract 20-byte EVM address from potentially 32-byte padded format
  // 32-byte format: 0x000000000000000000000000<20-byte-address>
  // 20-byte format: 0x<20-byte-address>
  let evmTokenAddress = tokenAddress;
  if (tokenAddress.length === 66) {
    // 32-byte padded (0x + 64 chars) - extract last 40 chars
    evmTokenAddress = "0x" + tokenAddress.slice(-40);
  }

  const tx = await solver.sendTransaction({
    to: hre.ethers.getAddress(evmTokenAddress),
    data: data,
  });

  const receipt = await tx.wait();

  if (receipt.status === 1) {
    console.log("SUCCESS");
    console.log("Transaction hash:", receipt.hash);
    console.log("Recipient:", recipient);
    console.log("Amount:", amount);
    console.log("Intent ID:", intentId);
  } else {
    const error = new Error("Transaction failed");
    console.error("Error:", error.message);
    if (require.main === module) {
      process.exit(1);
    }
    throw error;
  }
}

// Export main function for testing
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error:", error.message);
      process.exit(1);
    });
}

module.exports = { main };

