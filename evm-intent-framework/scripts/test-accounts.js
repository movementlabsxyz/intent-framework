const hre = require("hardhat");

async function main() {
  try {
    const signers = await hre.ethers.getSigners();
    // Account 0 = deployer, Account 1 = Alice, Account 2 = Bob
    console.log('Got signers:', signers.length);
    console.log('Deployer:', signers[0].address);
    console.log('Alice:', signers[1].address);
    console.log('Bob:', signers[2].address);
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

