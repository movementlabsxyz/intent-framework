//! Hardhat test accounts information utility
//!
//! This script outputs addresses and balances for the standard Hardhat test accounts.
//! Account 0 = deployer/verifier, Account 1 = Alice, Account 2 = Bob

const hre = require('hardhat');

/// Outputs test account addresses and balances
///
/// Outputs environment variable format strings for Alice, Bob, and Verifier addresses,
/// as well as their native ETH balances.
///
/// # Returns
/// Outputs ALICE_ADDRESS, BOB_ADDRESS, VERIFIER_ADDRESS, ALICE_BALANCE, and BOB_BALANCE.
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
