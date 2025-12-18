//! USDcon token deployment utility
//!
//! This script deploys a MockERC20 token as USDcon for testing on connected EVM chains.

const hre = require("hardhat");

/// Deploys USDcon token
///
/// Deploys a MockERC20 contract with name "USDcon" and symbol "USDcon".
/// Uses 6 decimals (like USDC/USDT).
///
/// # Returns
/// Outputs token address on success.
async function main() {
  console.log("Deploying USDcon token...");

  const [deployer] = await hre.ethers.getSigners();
  
  console.log("Deploying with account:", deployer.address);

  // Deploy MockERC20 as USDcon with 6 decimals (matching MVM, like USDC/USDT)
  const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
  const token = await MockERC20.deploy("USDcon", "USDcon", 6);

  await token.waitForDeployment();

  const tokenAddress = await token.getAddress();
  console.log("USDcon deployed to:", tokenAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

