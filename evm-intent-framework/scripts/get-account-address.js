const hre = require("hardhat");

async function main() {
  // Get account index from environment variable or command line argument
  // Defaults to 0 (Alice) if not provided
  const accountIndex = process.env.ACCOUNT_INDEX 
    ? parseInt(process.env.ACCOUNT_INDEX, 10)
    : (process.argv[2] ? parseInt(process.argv[2], 10) : 0);
  
  if (isNaN(accountIndex) || accountIndex < 0) {
    console.error("Error: Invalid account index. Must be a non-negative integer.");
    process.exit(1);
  }
  
  const signers = await hre.ethers.getSigners();
  
  if (accountIndex >= signers.length) {
    console.error(`Error: Account index ${accountIndex} is out of range. Only ${signers.length} accounts available.`);
    process.exit(1);
  }
  
  console.log(signers[accountIndex].address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

