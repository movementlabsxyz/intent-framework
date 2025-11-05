const hre = require("hardhat");

async function main() {
  try {
    const signers = await hre.ethers.getSigners();
    console.log('Got signers:', signers.length);
    console.log('Deployer (Acc 0):', signers[0].address);
    console.log('Alice (Acc 1):', signers[1].address);
    console.log('Bob (Acc 2):', signers[2].address);
  } catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

