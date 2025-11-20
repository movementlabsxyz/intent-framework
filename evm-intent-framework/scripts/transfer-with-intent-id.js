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

  const signers = await hre.ethers.getSigners();
  const solver = signers[2];

  const ERC20 = await hre.ethers.getContractFactory("MockERC20");
  const token = ERC20.attach(tokenAddress);

  const amountBigInt = BigInt(amount);
  const selector = "0xa9059cbb";
  
  const recipientClean = recipient.toLowerCase().replace(/^0x/, "");
  const intentIdClean = intentId.toLowerCase().replace(/^0x/, "");
  const recipientPadded = "0".repeat(24) + recipientClean;
  
  const amountHex = amountBigInt.toString(16);
  const amountPadded = "0".repeat(64 - amountHex.length) + amountHex;
  const intentIdPadded = intentIdClean.padStart(64, "0");
  
  const data = selector + recipientPadded + amountPadded + intentIdPadded;

  const tx = await solver.sendTransaction({
    to: tokenAddress,
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

