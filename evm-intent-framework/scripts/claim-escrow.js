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

  // Get solver private key from environment (for testnet) or use Hardhat signers (for local testing)
  let solver;
  if (process.env.BASE_SOLVER_PRIVATE_KEY) {
    // Testnet: Create wallet from private key
    const provider = hre.ethers.provider;
    solver = new hre.ethers.Wallet(process.env.BASE_SOLVER_PRIVATE_KEY, provider);
  } else {
    // Local testing: Use Hardhat signers
    const signers = await hre.ethers.getSigners();
    if (signers.length < 3) {
      throw new Error(`Expected at least 3 signers for local testing, but got ${signers.length}. For testnet, set BASE_SOLVER_PRIVATE_KEY environment variable.`);
    }
    solver = signers[2];
  }
  
  const escrow = await hre.ethers.getContractAt("IntentEscrow", escrowAddress);
  const intentId = BigInt(intentIdHex);
  const signature = `0x${signatureHex}`;
  
  try {
    const tx = await escrow.connect(solver).claim(intentId, signature);
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
