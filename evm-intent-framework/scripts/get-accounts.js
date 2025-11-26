//! Hardhat test accounts information utility
//!
//! This script outputs addresses and balances for the standard Hardhat test accounts.
//! Account 0 = deployer/verifier, Account 1 = requester, Account 2 = solver

const hre = require('hardhat');

/// Outputs test account addresses and balances
///
/// Outputs environment variable format strings for Requester, Solver, and Verifier addresses,
/// as well as their native ETH balances.
///
/// # Returns
/// Outputs REQUESTER_ADDRESS, SOLVER_ADDRESS, VERIFIER_ADDRESS, REQUESTER_BALANCE, and SOLVER_BALANCE.
async function main() {
  const signers = await hre.ethers.getSigners();
  
  // Account 0 = deployer/verifier, Account 1 = requester, Account 2 = solver
  console.log('REQUESTER_ADDRESS=' + signers[1].address);
  console.log('SOLVER_ADDRESS=' + signers[2].address);
  console.log('VERIFIER_ADDRESS=' + signers[0].address); // Verifier is account 0 (Deployer)
  
  const requesterBalance = await hre.ethers.provider.getBalance(signers[1].address);
  const solverBalance = await hre.ethers.provider.getBalance(signers[2].address);
  
  console.log('REQUESTER_BALANCE=' + requesterBalance.toString());
  console.log('SOLVER_BALANCE=' + solverBalance.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
