const hre = require("hardhat");

async function main() {
  console.log("Deploying MockERC20 token...");

  const [deployer] = await hre.ethers.getSigners();
  
  console.log("Deploying with account:", deployer.address);

  // Deploy MockERC20
  const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
  const token = await MockERC20.deploy("Test Token", "TEST");

  await token.waitForDeployment();

  const tokenAddress = await token.getAddress();
  console.log("MockERC20 deployed to:", tokenAddress);

  // Mint some tokens to deployer for testing
  const mintAmount = hre.ethers.parseEther("1000000000");
  await token.mint(deployer.address, mintAmount);
  console.log("Minted", mintAmount.toString(), "tokens to", deployer.address);

  console.log("\n✅ Token deployment successful!");
  console.log("Token address:", tokenAddress);
  console.log("Deployer balance:", (await token.balanceOf(deployer.address)).toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

