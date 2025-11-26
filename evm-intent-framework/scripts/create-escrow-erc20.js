//! ERC20 escrow creation utility
//!
//! This script creates an escrow on the IntentEscrow contract using ERC20 tokens.
//! Requires prior approval of the escrow contract to spend tokens.

const hre = require("hardhat");

/// Creates an ERC20 escrow for an intent
///
/// # Environment Variables
/// - `ESCROW_ADDRESS`: IntentEscrow contract address
/// - `TOKEN_ADDRESS`: ERC20 token address
/// - `INTENT_ID_EVM`: Intent ID in EVM format (uint256, hex with 0x prefix)
/// - `AMOUNT`: Amount of tokens to lock in escrow (smallest unit, decimal string)
/// - `RESERVED_SOLVER`: Solver address that will receive funds
///
/// # Returns
/// Outputs success message with intent ID on success.
async function main() {
  const escrowAddress = process.env.ESCROW_ADDRESS;
  const tokenAddress = process.env.TOKEN_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;
  const amount = process.env.AMOUNT;
  const reservedSolver = process.env.RESERVED_SOLVER;

  if (!escrowAddress || !tokenAddress || !intentIdHex || !amount || !reservedSolver) {
    throw new Error("Missing required environment variables: ESCROW_ADDRESS, TOKEN_ADDRESS, INTENT_ID_EVM, AMOUNT, RESERVED_SOLVER");
  }

  const signers = await hre.ethers.getSigners();
  const requester = signers[1]; // Requester is signer[1]
  
  const escrow = await hre.ethers.getContractAt("IntentEscrow", escrowAddress);
  const token = await hre.ethers.getContractAt("MockERC20", tokenAddress);
  
  const intentId = BigInt(intentIdHex);
  const amountBigInt = BigInt(amount);
  
  // Approve escrow contract to spend tokens
  console.log("Approving escrow contract to spend tokens...");
  await token.connect(requester).approve(escrowAddress, amountBigInt);
  
  // Create escrow with ERC20 token
  console.log("Creating escrow...");
  await escrow.connect(requester).createEscrow(intentId, tokenAddress, amountBigInt, reservedSolver);
  console.log("Escrow created for intent (ERC20):", intentId.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

