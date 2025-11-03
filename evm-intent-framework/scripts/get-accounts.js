const hre = require('hardhat');

async function main() {
  const signers = await hre.ethers.getSigners();
  
  console.log('ALICE_ADDRESS=' + signers[0].address);
  console.log('BOB_ADDRESS=' + signers[1].address);
  console.log('VERIFIER_ADDRESS=' + signers[1].address); // Verifier is also account 1
  
  const aliceBalance = await hre.ethers.provider.getBalance(signers[0].address);
  const bobBalance = await hre.ethers.provider.getBalance(signers[1].address);
  
  console.log('ALICE_BALANCE=' + aliceBalance.toString());
  console.log('BOB_BALANCE=' + bobBalance.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

