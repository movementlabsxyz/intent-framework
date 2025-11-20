//! MockERC20 token minting utility
//!
//! This script mints tokens from a MockERC20 contract to a specified recipient.
//! Uses the deployer account (Account 0) to mint tokens.

const hre = require("hardhat");

/// Mints tokens to a recipient address
///
/// # Environment Variables
/// - `TOKEN_ADDRESS`: MockERC20 token contract address
/// - `RECIPIENT`: Address to receive minted tokens
/// - `AMOUNT`: Amount to mint in base units (wei for 18 decimals)
///
/// # Returns
/// Outputs success message with minted amount and recipient on success.
async function main() {
  const tokenAddress = process.env.TOKEN_ADDRESS;
  const recipient = process.env.RECIPIENT;
  const amount = process.env.AMOUNT;

  if (!tokenAddress || !recipient || !amount) {
    const error = new Error("Missing required environment variables: TOKEN_ADDRESS, RECIPIENT, AMOUNT");
    console.error("Error:", error.message);
    if (require.main === module) {
      process.exit(1);
    }
    throw error;
  }

  const signers = await hre.ethers.getSigners();
  const deployer = signers[0];

  const ERC20 = await hre.ethers.getContractFactory("MockERC20");
  const token = ERC20.attach(tokenAddress);

  const amountBigInt = BigInt(amount);
  await token.connect(deployer).mint(recipient, amountBigInt);

  console.log("SUCCESS");
  console.log("Minted", amount, "tokens to", recipient);
}

// Export main function for testing
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Error:", error.message);
      process.exit(1);
    });
}

module.exports = { main };

