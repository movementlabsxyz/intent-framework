//! ETH deposit utility for existing escrows
//!
//! This script deposits additional ETH into an existing escrow on the IntentEscrow contract.

const hre = require("hardhat");

/// Deposits ETH into an existing escrow
///
/// # Environment Variables
/// - `ESCROW_ADDRESS`: IntentEscrow contract address
/// - `INTENT_ID_EVM`: Intent ID in EVM format (uint256, hex with 0x prefix)
/// - `ETH_AMOUNT_WEI`: Amount of ETH to deposit (wei, decimal string)
///
/// # Returns
/// Outputs success message with deposited amount on success.
async function main() {
  const escrowAddress = process.env.ESCROW_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;
  const amountWei = process.env.ETH_AMOUNT_WEI;

  if (!escrowAddress || !intentIdHex || !amountWei) {
    throw new Error("Missing required environment variables: ESCROW_ADDRESS, INTENT_ID_EVM, ETH_AMOUNT_WEI");
  }

  const signers = await hre.ethers.getSigners();
  const requester = signers[1]; // Requester is signer[1]
  const escrow = await hre.ethers.getContractAt("IntentEscrow", escrowAddress);
  const intentId = BigInt(intentIdHex);
  const amount = BigInt(amountWei);
  
  // Deposit ETH (pass value in transaction)
  const tx = await escrow.connect(requester).deposit(intentId, amount, { value: amount });
  await tx.wait();
  console.log("Deposited", amount.toString(), "wei (ETH) into escrow");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
