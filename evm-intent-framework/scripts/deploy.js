const hre = require("hardhat");

async function main() {
  console.log("Deploying IntentVault...");

  // Get signers
  const [deployer] = await hre.ethers.getSigners();
  
  // Get verifier address from environment variable - REQUIRED, no fallback
  const verifierAddress = process.env.VERIFIER_ADDRESS;
  
  if (!verifierAddress) {
    throw new Error("VERIFIER_ADDRESS environment variable is required. The verifier address must be set for proper signature verification.");
  }
  
  const verifierAddr = verifierAddress;
  console.log("Using verifier address from config:", verifierAddr);
  
  console.log("Deploying with account:", deployer.address);
  console.log("Verifier address:", verifierAddr);

  // Deploy vault with verifier address
  const IntentVault = await hre.ethers.getContractFactory("IntentVault");
  const vault = await IntentVault.deploy(verifierAddr);

  await vault.waitForDeployment();

  const vaultAddress = await vault.getAddress();
  console.log("IntentVault deployed to:", vaultAddress);
  console.log("Verifier set to:", verifierAddr);

  // Verify deployment
  const verifierFromContract = await vault.verifier();
  console.log("Verifier from contract:", verifierFromContract);
  
  if (verifierFromContract.toLowerCase() !== verifierAddr.toLowerCase()) {
    throw new Error("Verifier address mismatch!");
  }

  console.log("\n✅ Deployment successful!");
  console.log("Contract address:", vaultAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

