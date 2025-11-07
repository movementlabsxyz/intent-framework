const hre = require("hardhat");

async function main() {
  const vaultAddress = process.env.VAULT_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;

  if (!vaultAddress || !intentIdHex) {
    throw new Error("Missing required environment variables: VAULT_ADDRESS, INTENT_ID_EVM");
  }

  const signers = await hre.ethers.getSigners();
  const vault = await hre.ethers.getContractAt("IntentVault", vaultAddress);
  const intentId = BigInt(intentIdHex);
  
  // Use address(0) for ETH
  // Account 0 = deployer, Account 1 = Alice, Account 2 = Bob
  // Expiry is now contract-defined (1 hour), no longer a parameter
  const ethAddress = "0x0000000000000000000000000000000000000000";
  
  await vault.connect(signers[1]).initializeVault(intentId, ethAddress);
  console.log("Vault initialized for intent (ETH):", intentId.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

