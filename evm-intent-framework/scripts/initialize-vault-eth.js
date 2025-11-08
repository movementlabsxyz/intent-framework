const hre = require("hardhat");

async function main() {
  const escrowAddress = process.env.ESCROW_ADDRESS || process.env.VAULT_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;

  if (!escrowAddress || !intentIdHex) {
    throw new Error("Missing required environment variables: ESCROW_ADDRESS (or VAULT_ADDRESS), INTENT_ID_EVM");
  }

  const signers = await hre.ethers.getSigners();
  const escrow = await hre.ethers.getContractAt("IntentEscrow", escrowAddress);
  const intentId = BigInt(intentIdHex);
  
  // Use address(0) for ETH
  // Account 0 = deployer, Account 1 = Alice, Account 2 = Bob
  // Expiry is now contract-defined (1 hour), no longer a parameter
  const ethAddress = "0x0000000000000000000000000000000000000000";
  
  await escrow.connect(signers[1]).initializeEscrow(intentId, ethAddress);
  console.log("Escrow initialized for intent (ETH):", intentId.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

