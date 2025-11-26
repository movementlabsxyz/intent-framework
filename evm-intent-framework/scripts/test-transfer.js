//! Native ETH transfer test utility
//!
//! This script performs a simple native ETH transfer from requester (Account 1) to solver (Account 2)
//! for testing purposes.

const hre = require("hardhat");

/// Performs test ETH transfer
///
/// Transfers 1 ETH from requester to solver and outputs solver's balance after the transfer.
///
/// # Returns
/// Outputs success message with solver's balance after transfer on success.
async function main() {
  try {
    const signers = await hre.ethers.getSigners();
    const requester = signers[1];  // Requester (Account 1)
    const solver = signers[2]; // Solver (Account 2)
    
    const amount = hre.ethers.parseEther('1.0'); // 1 ETH
    
    const tx = await requester.sendTransaction({
      to: solver.address,
      value: amount
    });
    
    await tx.wait();
    
    const solverBalanceAfter = await hre.ethers.provider.getBalance(solver.address);
    console.log('SUCCESS: Solver balance after transfer:', solverBalanceAfter.toString());
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
