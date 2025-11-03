const hre = require("hardhat");

async function main() {
  const signers = await hre.ethers.getSigners();
  const balance = await hre.ethers.provider.getBalance(signers[1].address);
  console.log(balance.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

