//! ERC20 token balance query utility
//!
//! This script queries the token balance of an account for a given ERC20 token contract.

const hre = require("hardhat");

/// Gets token balance for an account
///
/// # Environment Variables
/// - `TOKEN_ADDRESS`: ERC20 token contract address
/// - `ACCOUNT`: Account address to query balance for
///
/// # Returns
/// Outputs balance as a decimal string (base units) on success.
async function main() {
  const tokenAddress = process.env.TOKEN_ADDRESS;
  const account = process.env.ACCOUNT;

  if (!tokenAddress || !account) {
    const error = new Error("Missing required environment variables: TOKEN_ADDRESS, ACCOUNT");
    console.error("Error:", error.message);
    if (require.main === module) {
      process.exit(1);
    }
    throw error;
  }

  const ERC20 = await hre.ethers.getContractFactory("MockERC20");
  const token = ERC20.attach(tokenAddress);

  const balance = await token.balanceOf(account);
  console.log(balance.toString());
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

