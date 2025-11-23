//! ETH escrow creation utility
//!
//! This script creates an escrow on the IntentEscrow contract using native ETH.
//! Uses address(0) to represent ETH as the token address.

const hre = require("hardhat");

/// Creates an ETH escrow for an intent
///
/// # Environment Variables
/// - `ESCROW_ADDRESS`: IntentEscrow contract address
/// - `INTENT_ID_EVM`: Intent ID in EVM format (uint256, hex with 0x prefix)
/// - `ETH_AMOUNT_WEI`: Amount of ETH to lock in escrow (wei, decimal string)
/// - `RESERVED_SOLVER`: Optional solver address (defaults to zero address)
///
/// # Returns
/// Outputs success message with intent ID on success.
async function main() {
  const escrowAddress = process.env.ESCROW_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;
  const amountWei = process.env.ETH_AMOUNT_WEI;
  const reservedSolver = process.env.RESERVED_SOLVER || "0x0000000000000000000000000000000000000000";

  if (!escrowAddress || !intentIdHex || !amountWei) {
    throw new Error("Missing required environment variables: ESCROW_ADDRESS, INTENT_ID_EVM, ETH_AMOUNT_WEI");
  }

  const signers = await hre.ethers.getSigners();
  const escrow = await hre.ethers.getContractAt("IntentEscrow", escrowAddress);
  const intentId = BigInt(intentIdHex);
  const amount = BigInt(amountWei);
  
  // Use address(0) for ETH
  const ethAddress = "0x0000000000000000000000000000000000000000";
  
  await escrow.connect(signers[1]).createEscrow(intentId, ethAddress, amount, reservedSolver, { value: amount });
  console.log("Escrow created for intent (ETH):", intentId.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

