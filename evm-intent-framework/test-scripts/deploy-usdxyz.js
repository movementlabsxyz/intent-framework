//! USDxyz token deployment utility
//!
//! This script deploys a MockERC20 token as USDxyz for testing.

const hre = require("hardhat");

/// Deploys USDxyz token
///
/// Deploys a MockERC20 contract with name "USDxyz" and symbol "USDxyz".
/// Uses 6 decimals (matching MVM USDxyz, like USDC/USDT).
///
/// # Returns
/// Outputs token address on success.
async function main() {
  console.log("Deploying USDxyz token...");

  const [deployer] = await hre.ethers.getSigners();
  
  console.log("Deploying with account:", deployer.address);

  // Deploy MockERC20 as USDxyz with 6 decimals (matching MVM, like USDC/USDT)
  const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
  const token = await MockERC20.deploy("USDxyz", "USDxyz", 6);

  await token.waitForDeployment();

  const tokenAddress = await token.getAddress();
  console.log("USDxyz deployed to:", tokenAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

