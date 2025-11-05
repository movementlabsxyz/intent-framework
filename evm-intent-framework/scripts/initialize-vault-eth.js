const hre = require("hardhat");

async function main() {
  const vaultAddress = process.env.VAULT_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;
  const expiry = parseInt(process.env.EXPIRY_TIME_EVM);

  if (!vaultAddress || !intentIdHex || !expiry) {
    throw new Error("Missing required environment variables: VAULT_ADDRESS, INTENT_ID_EVM, EXPIRY_TIME_EVM");
  }

  const signers = await hre.ethers.getSigners();
  const maker = signers[1]; // Alice (Account 1)
  
  // Use contract factory to get ABI, then create contract instance directly
  // This avoids the name resolution issue with getContractAt on localhost network
  const IntentVaultFactory = await hre.ethers.getContractFactory("IntentVault", maker);
  const vault = IntentVaultFactory.attach(vaultAddress);
  
  const intentId = BigInt(intentIdHex);
  
  // Use address(0) for ETH
  const ethAddress = "0x0000000000000000000000000000000000000000";
  
  await vault.initializeVault(intentId, ethAddress, expiry);
  console.log("Vault initialized for intent (ETH):", intentId.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

