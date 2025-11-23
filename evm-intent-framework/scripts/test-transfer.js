//! Native ETH transfer test utility
//!
//! This script performs a simple native ETH transfer from Alice (Account 1) to Bob (Account 2)
//! for testing purposes.

const hre = require("hardhat");

/// Performs test ETH transfer
///
/// Transfers 1 ETH from Alice to Bob and outputs Bob's balance after the transfer.
///
/// # Returns
/// Outputs success message with Bob's balance after transfer on success.
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

