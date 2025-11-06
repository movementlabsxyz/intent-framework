const hre = require("hardhat");

async function main() {
  const vaultAddress = process.env.VAULT_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;
  const signatureHex = process.env.SIGNATURE_HEX;

  if (!vaultAddress || !intentIdHex || !signatureHex) {
    throw new Error("Missing required environment variables: VAULT_ADDRESS, INTENT_ID_EVM, SIGNATURE_HEX");
  }

  const signers = await hre.ethers.getSigners();
  const vault = await hre.ethers.getContractAt("IntentVault", vaultAddress);
  const intentId = BigInt(intentIdHex);
  const approvalValue = 1;
  const signature = `0x${signatureHex}`;
  
  try {
    // Account 0 = deployer, Account 1 = Alice, Account 2 = Bob
    const tx = await vault.connect(signers[2]).claim(intentId, approvalValue, signature);
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

