//! Escrow status query utility
//!
//! This script queries the claim status of an escrow on the IntentEscrow contract.

const hre = require("hardhat");

/// Gets escrow claim status
///
/// # Environment Variables
/// - `ESCROW_ADDRESS`: IntentEscrow contract address
/// - `INTENT_ID_EVM`: Intent ID in EVM format (uint256, hex with 0x prefix)
///
/// # Returns
/// Outputs "isClaimed: true" or "isClaimed: false" on success.
async function main() {
  const escrowAddress = process.env.ESCROW_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;

  if (!escrowAddress || !intentIdHex) {
    const error = new Error("Missing required environment variables: ESCROW_ADDRESS, INTENT_ID_EVM");
    console.error("Error:", error.message);
    if (require.main === module) {
      process.exit(1);
    }
    throw error;
  }

  const IntentEscrow = await hre.ethers.getContractFactory("IntentEscrow");
  const escrow = IntentEscrow.attach(escrowAddress);

  // Convert hex intent ID to BigInt
  const intentId = BigInt(intentIdHex);

  try {
    const escrowData = await escrow.getEscrow(intentId);
    const isClaimed = escrowData.isClaimed;
    console.log(`isClaimed: ${isClaimed}`);
  } catch (error) {
    // If escrow doesn't exist, getEscrow will revert
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

