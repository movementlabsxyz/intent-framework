//! Create escrow for inflow intent
//!
//! This script creates an escrow on the IntentEscrow contract for an inflow intent.
//! It approves the token and deposits funds atomically via createEscrow().
//!
//! Environment Variables:
//!   - ESCROW_CONTRACT_ADDRESS: IntentEscrow contract address
//!   - INTENT_ID: Intent ID from Movement (hex string with 0x prefix)
//!   - TOKEN_ADDRESS: ERC20 token address (USDC)
//!   - AMOUNT: Amount to deposit (in smallest units, e.g., 1000000 = 1 USDC)
//!   - SOLVER_ADDRESS: Solver's EVM address (reserved for claiming)
//!   - REQUESTER_PRIVATE_KEY: Private key of the requester (for signing tx)
//!   - RPC_URL: Base Sepolia RPC URL

const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main() {
  // Load environment variables
  const escrowAddress = process.env.ESCROW_CONTRACT_ADDRESS;
  const intentIdHex = process.env.INTENT_ID;
  const tokenAddress = process.env.TOKEN_ADDRESS;
  const amount = process.env.AMOUNT;
  const solverAddress = process.env.SOLVER_ADDRESS;
  const requesterPrivateKey = process.env.REQUESTER_PRIVATE_KEY;

  // Validate required environment variables
  if (!escrowAddress) throw new Error("ESCROW_CONTRACT_ADDRESS not set");
  if (!intentIdHex) throw new Error("INTENT_ID not set");
  if (!tokenAddress) throw new Error("TOKEN_ADDRESS not set");
  if (!amount) throw new Error("AMOUNT not set");
  if (!solverAddress) throw new Error("SOLVER_ADDRESS not set");
  if (!requesterPrivateKey) throw new Error("REQUESTER_PRIVATE_KEY not set");

  console.log("Creating escrow for inflow intent...");
  console.log("  Escrow Contract:", escrowAddress);
  console.log("  Intent ID:", intentIdHex);
  console.log("  Token:", tokenAddress);
  console.log("  Amount:", amount);
  console.log("  Solver:", solverAddress);

  // Convert intent ID to uint256
  // Movement addresses are 32 bytes, EVM uint256 is also 32 bytes
  const intentId = BigInt(intentIdHex);
  console.log("  Intent ID (uint256):", intentId.toString());

  // Create wallet from private key
  const provider = new ethers.JsonRpcProvider(process.env.RPC_URL || process.env.BASE_SEPOLIA_RPC_URL);
  const wallet = new ethers.Wallet(requesterPrivateKey, provider);
  console.log("  Requester:", wallet.address);

  // Get contract instances
  const escrow = await ethers.getContractAt("IntentEscrow", escrowAddress, wallet);
  
  // Use minimal ERC20 ABI for approve/allowance/balanceOf
  const erc20Abi = [
    "function approve(address spender, uint256 amount) external returns (bool)",
    "function allowance(address owner, address spender) external view returns (uint256)",
    "function balanceOf(address account) external view returns (uint256)"
  ];
  const token = new ethers.Contract(tokenAddress, erc20Abi, wallet);

  // Check token balance
  const balance = await token.balanceOf(wallet.address);
  console.log("  Token balance:", balance.toString());
  
  if (balance < BigInt(amount)) {
    throw new Error(`Insufficient token balance. Have: ${balance}, Need: ${amount}`);
  }

  // Check and set allowance
  const currentAllowance = await token.allowance(wallet.address, escrowAddress);
  console.log("  Current allowance:", currentAllowance.toString());

  if (currentAllowance < BigInt(amount)) {
    console.log("  Approving token transfer...");
    const approveTx = await token.approve(escrowAddress, amount);
    await approveTx.wait();
    console.log("  ✅ Token approved");
  } else {
    console.log("  ✅ Sufficient allowance already set");
  }

  // Create escrow (atomic: creates escrow and deposits funds)
  console.log("  Creating escrow and depositing funds...");
  const tx = await escrow.createEscrow(intentId, tokenAddress, amount, solverAddress);
  const receipt = await tx.wait();
  
  console.log("");
  console.log("✅ Escrow created successfully!");
  console.log("  Transaction hash:", receipt.hash);
  console.log("  Intent ID:", intentIdHex);
  console.log("  Amount deposited:", amount);
  console.log("  Solver (reserved):", solverAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error.message);
    process.exit(1);
  });

