const hre = require("hardhat");

async function main() {
  try {
    const signers = await hre.ethers.getSigners();
    const alice = signers[1]; // Alice (Account 1)
    const bob = signers[2];   // Bob (Account 2)
    
    const amount = hre.ethers.parseEther('1.0'); // 1 ETH
    
    const tx = await alice.sendTransaction({
      to: bob.address,
      value: amount
    });
    
    await tx.wait();
    
    const bobBalanceAfter = await hre.ethers.provider.getBalance(bob.address);
    console.log('SUCCESS: Bob balance after transfer:', bobBalanceAfter.toString());
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

