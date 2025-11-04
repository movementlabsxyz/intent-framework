const hre = require("hardhat");

async function main() {
  const vaultAddress = process.env.VAULT_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;
  const expiry = parseInt(process.env.EXPIRY_TIME_EVM);

  if (!vaultAddress || !intentIdHex || !expiry) {
    throw new Error("Missing required environment variables: VAULT_ADDRESS, INTENT_ID_EVM, EXPIRY_TIME_EVM");
  }

  const signers = await hre.ethers.getSigners();
  const vault = await hre.ethers.getContractAt("IntentVault", vaultAddress);
  const intentId = BigInt(intentIdHex);
  
  // Use address(0) for ETH
  const ethAddress = "0x0000000000000000000000000000000000000000";
  
  await vault.connect(signers[0]).initializeVault(intentId, ethAddress, expiry);
  console.log("Vault initialized for intent (ETH):", intentId.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

