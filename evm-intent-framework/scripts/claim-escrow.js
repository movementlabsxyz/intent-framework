const hre = require("hardhat");

async function main() {
  const escrowAddress = process.env.ESCROW_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;
  const signatureHex = process.env.SIGNATURE_HEX;

  if (!escrowAddress || !intentIdHex || !signatureHex) {
    throw new Error("Missing required environment variables: ESCROW_ADDRESS, INTENT_ID_EVM, SIGNATURE_HEX");
  }

  const signers = await hre.ethers.getSigners();
  const escrow = await hre.ethers.getContractAt("IntentEscrow", escrowAddress);
  const intentId = BigInt(intentIdHex);
  const approvalValue = 1;
  const signature = `0x${signatureHex}`;
  
  try {
    // Account 0 = deployer, Account 1 = Alice, Account 2 = Bob
    const tx = await escrow.connect(signers[2]).claim(intentId, approvalValue, signature);
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

