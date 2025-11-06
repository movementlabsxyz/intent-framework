const hre = require("hardhat");

async function main() {
  const vaultAddress = process.env.VAULT_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;
  const amountWei = process.env.ETH_AMOUNT_WEI;

  if (!vaultAddress || !intentIdHex || !amountWei) {
    throw new Error("Missing required environment variables: VAULT_ADDRESS, INTENT_ID_EVM, ETH_AMOUNT_WEI");
  }

  const signers = await hre.ethers.getSigners();
  const vault = await hre.ethers.getContractAt("IntentVault", vaultAddress);
  const intentId = BigInt(intentIdHex);
  const amount = BigInt(amountWei);
  
  // Deposit ETH (pass value in transaction)
  // Account 0 = deployer, Account 1 = Alice, Account 2 = Bob
  const tx = await vault.connect(signers[1]).deposit(intentId, amount, { value: amount });
  await tx.wait();
  console.log("Deposited", amount.toString(), "wei (ETH) into vault");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

