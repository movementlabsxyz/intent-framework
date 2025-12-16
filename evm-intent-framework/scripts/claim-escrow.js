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
  
  const escrow = await hre.ethers.getContractAt("IntentEscrow", escrowAddress);
  const intentId = BigInt(intentIdHex);
  const signature = `0x${signatureHex}`;
  
  // Check if escrow is already claimed before attempting to claim
  let wasAlreadyClaimed = false;
  try {
    const escrowData = await escrow.getEscrow(intentId);
    if (escrowData.isClaimed) {
      wasAlreadyClaimed = true;
      console.log("Escrow already claimed - skipping");
      // Don't exit here - let the caller handle the balance check
      // The escrow was already claimed, so funds were already transferred
    }
  } catch (error) {
    // If getEscrow fails, escrow might not exist - continue to claim attempt
    // which will provide a more specific error
  }
  
  // If already claimed, exit early (funds were already transferred)
  if (wasAlreadyClaimed) {
    console.log("Escrow released successfully!");
    process.exit(0);
  }
  
  try {
    const tx = await escrow.connect(solver).claim(intentId, signature);
    const receipt = await tx.wait();
    console.log("Claim transaction hash:", receipt.hash);
    console.log("Escrow released successfully!");
  } catch (error) {
    // Check if error is EscrowAlreadyClaimed - handle gracefully
    if (error.message && error.message.includes("EscrowAlreadyClaimed")) {
      console.log("Escrow already claimed - skipping");
      console.log("Escrow released successfully!");
      process.exit(0);
    }
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
