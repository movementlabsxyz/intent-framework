const hre = require("hardhat");

async function main() {
  console.log("Deploying IntentVault...");

  // Get signers
  const [deployer, verifier] = await hre.ethers.getSigners();
  
  console.log("Deploying with account:", deployer.address);
  console.log("Verifier address:", verifier.address);

  // Deploy vault with verifier address
  const IntentVault = await hre.ethers.getContractFactory("IntentVault");
  const vault = await IntentVault.deploy(verifier.address);

  await vault.waitForDeployment();

  const vaultAddress = await vault.getAddress();
  console.log("IntentVault deployed to:", vaultAddress);
  console.log("Verifier set to:", verifier.address);

  // Verify deployment
  const verifierFromContract = await vault.verifier();
  console.log("Verifier from contract:", verifierFromContract);
  
  if (verifierFromContract.toLowerCase() !== verifier.address.toLowerCase()) {
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

