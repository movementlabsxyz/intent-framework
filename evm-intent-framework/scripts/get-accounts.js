const hre = require('hardhat');

async function main() {
  const signers = await hre.ethers.getSigners();
  
  // Account 0 = deployer/verifier, Account 1 = Alice, Account 2 = Bob
  console.log('ALICE_ADDRESS=' + signers[1].address);
  console.log('BOB_ADDRESS=' + signers[2].address);
  console.log('VERIFIER_ADDRESS=' + signers[0].address); // Verifier is account 0 (Deployer)
  
  const aliceBalance = await hre.ethers.provider.getBalance(signers[1].address);
  const bobBalance = await hre.ethers.provider.getBalance(signers[2].address);
  
  console.log('ALICE_BALANCE=' + aliceBalance.toString());
  console.log('BOB_BALANCE=' + bobBalance.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
