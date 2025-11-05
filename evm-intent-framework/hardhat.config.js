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
      // For tests, use automatic mining (default)
      // For localhost node, use manual mining with interval
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
      accounts: {
        // Hardhat default accounts (same as when running hardhat node)
        mnemonic: "test test test test test test test test test test test junk",
      },
    },
  },
};

