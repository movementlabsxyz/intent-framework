//! IntentEscrow contract deployment utility
//!
//! This script deploys the IntentEscrow contract with a specified verifier address.
//! If no verifier address is provided via environment variable, uses the deployer account.

const hre = require("hardhat");

/// Deploys IntentEscrow contract with verifier
///
/// # Environment Variables
/// - `VERIFIER_ADDRESS`: Optional verifier Ethereum address (defaults to deployer address)
///
/// # Returns
/// Outputs contract address, verifier address, and deployment status on success.
async function main() {
  console.log("Deploying IntentEscrow...");

  // Get signers
  const [deployer] = await hre.ethers.getSigners();
  
  // Get verifier address from environment variable or use Hardhat account 1 as fallback
  const verifierAddress = process.env.VERIFIER_ADDRESS;
  let verifierAddr;
  
  if (verifierAddress) {
    verifierAddr = verifierAddress;
    console.log("Using verifier address from config:", verifierAddr);
  } else {
    // Fallback to deployer as verifier
    // Account 0 = deployer/verifier, Account 1 = requester, Account 2 = solver
    verifierAddr = deployer.address;
    console.log("Using deployer as verifier:", verifierAddr);
  }
  
  console.log("Deploying with account:", deployer.address);
  console.log("Verifier address:", verifierAddr);

  // Deploy escrow with verifier address
  const IntentEscrow = await hre.ethers.getContractFactory("IntentEscrow");
  const escrow = await IntentEscrow.deploy(verifierAddr);

  await escrow.waitForDeployment();

  const escrowAddress = await escrow.getAddress();
  console.log("IntentEscrow deployed to:", escrowAddress);
  console.log("Verifier set to:", verifierAddr);

  // Verify deployment
  const verifierFromContract = await escrow.verifier();
  console.log("Verifier from contract:", verifierFromContract);
  
  if (verifierFromContract.toLowerCase() !== verifierAddr.toLowerCase()) {
    throw new Error("Verifier address mismatch!");
  }

  console.log("\n✅ Deployment successful!");
  console.log("Contract address:", escrowAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
