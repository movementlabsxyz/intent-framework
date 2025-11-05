const hre = require('hardhat');

async function main() {
  const signers = await hre.ethers.getSigners();
  
  console.log('DEPLOYER_ADDRESS=' + signers[0].address); // Deployer (Account 0)
  console.log('ALICE_ADDRESS=' + signers[1].address); // Alice (Account 1)
  console.log('BOB_ADDRESS=' + signers[2].address); // Bob (Account 2)
  
  const deployerBalance = await hre.ethers.provider.getBalance(signers[0].address);
  const aliceBalance = await hre.ethers.provider.getBalance(signers[1].address);
  const bobBalance = await hre.ethers.provider.getBalance(signers[2].address);
  
  console.log('DEPLOYER_BALANCE=' + deployerBalance.toString());
  console.log('ALICE_BALANCE=' + aliceBalance.toString());
  console.log('BOB_BALANCE=' + bobBalance.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

