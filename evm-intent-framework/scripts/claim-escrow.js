//! Escrow claim utility
//!
//! This script claims an escrow on the IntentEscrow contract using a verifier signature.
//! The solver (Account 2) calls claim() to release the escrowed funds.

const hre = require("hardhat");

/// Claims an escrow with verifier signature
///
/// # Environment Variables
/// - `ESCROW_ADDRESS`: IntentEscrow contract address
/// - `INTENT_ID_EVM`: Intent ID in EVM format (uint256, hex with 0x prefix)
/// - `SIGNATURE_HEX`: Verifier ECDSA signature (hex string without 0x prefix)
///
/// # Returns
/// Outputs transaction hash and success message on success.
async function main() {
  const escrowAddress = process.env.ESCROW_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;
  const signatureHex = process.env.SIGNATURE_HEX;

  if (!escrowAddress || !intentIdHex || !signatureHex) {
    throw new Error("Missing required environment variables: ESCROW_ADDRESS, INTENT_ID_EVM, SIGNATURE_HEX");
  }

  const signers = await hre.ethers.getSigners();
  const escrow = await hre.ethers.getContractAt("IntentEscrow", escrowAddress);
  const intentId = BigInt(intentIdHex);
  const signature = `0x${signatureHex}`;
  
  try {
    // Account 0 = deployer, Account 1 = Alice, Account 2 = Bob
    const tx = await escrow.connect(signers[2]).claim(intentId, signature);
    const receipt = await tx.wait();
    console.log("Claim transaction hash:", receipt.hash);
    console.log("Escrow released successfully!");
  } catch (error) {
    console.error("Error claiming escrow:", error.message);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

