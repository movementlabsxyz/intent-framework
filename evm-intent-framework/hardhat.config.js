require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 31337,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
      accounts: {
        // Hardhat default accounts (same as when running hardhat node)
        mnemonic: "test test test test test test test test test test test junk",
      },
    },
    ...(process.env.BASE_SEPOLIA_RPC_URL ? {
      baseSepolia: {
        url: process.env.BASE_SEPOLIA_RPC_URL,
        chainId: 84532,
        // For testnet, scripts use BASE_SOLVER_PRIVATE_KEY directly via Wallet
        // For local testing, scripts use Hardhat signers
        accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [],
      },
    } : {}),
  },
};

