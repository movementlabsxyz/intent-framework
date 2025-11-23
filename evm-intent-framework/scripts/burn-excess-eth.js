//! Burn excess ETH utility
//!
//! This script burns (sends to 0x0) excess ETH from an account, leaving only a specified amount.
//!
//! # Environment Variables
//! - `ACCOUNT_INDEX`: Account index (0, 1, 2, etc.) to burn from
//! - `KEEP_AMOUNT_WEI`: Amount to keep in wei (decimal string)
//!
//! # Returns
//! Outputs success message with final balance on success.

const hre = require("hardhat");

/// Burns excess ETH from an account
///
/// Sends all ETH except KEEP_AMOUNT_WEI to the zero address (0x0) to burn it.
///
/// # Returns
/// Outputs success message with final balance on success.
async function main() {
  const accountIndex = process.env.ACCOUNT_INDEX;
  const keepAmountWei = process.env.KEEP_AMOUNT_WEI;

  if (!accountIndex) {
    throw new Error("Missing required environment variable: ACCOUNT_INDEX");
  }

  if (!keepAmountWei) {
    throw new Error("Missing required environment variable: KEEP_AMOUNT_WEI");
  }

  const signers = await hre.ethers.getSigners();
  const accountIndexNum = parseInt(accountIndex, 10);

  if (accountIndexNum < 0 || accountIndexNum >= signers.length) {
    throw new Error(`Account index ${accountIndexNum} is out of range. Only ${signers.length} accounts available.`);
  }

  const account = signers[accountIndexNum];
  const currentBalance = await hre.ethers.provider.getBalance(account.address);
  const keepAmount = BigInt(keepAmountWei);

  // Calculate amount to burn (current balance - keep amount - gas estimate)
  // We need to reserve some ETH for gas fees, so we'll estimate gas for the burn transaction
  const gasPrice = await hre.ethers.provider.getFeeData();
  const gasEstimate = 21000n; // Standard ETH transfer gas
  const gasCost = gasEstimate * (gasPrice.gasPrice || 0n);
  
  // Amount to burn = current balance - keep amount - gas cost
  const burnAmount = currentBalance > (keepAmount + gasCost) 
    ? currentBalance - keepAmount - gasCost
    : 0n;

  if (burnAmount <= 0n) {
    console.log("SUCCESS: No excess ETH to burn. Current balance:", currentBalance.toString(), "wei");
    console.log("Final balance:", currentBalance.toString(), "wei");
    return;
  }

  // Send excess to 0x0 to burn it
  const burnAddress = "0x0000000000000000000000000000000000000000";
  const tx = await account.sendTransaction({
    to: burnAddress,
    value: burnAmount
  });

  await tx.wait();

  const finalBalance = await hre.ethers.provider.getBalance(account.address);
  console.log("SUCCESS: Burned", burnAmount.toString(), "wei to 0x0");
  console.log("Final balance:", finalBalance.toString(), "wei");
  console.log("Expected to keep:", keepAmountWei, "wei");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error:", error.message);
    process.exit(1);
  });

