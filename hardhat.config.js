require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const url = "https://evm-rpc-testnet.sei-apis.com";
const wallet = process.env.PRIVATE_KEY;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    sei: {
      url: url,
      accounts: [wallet],
      chainId: 1328,
    },
    localhost: {
      url: "http://127.0.0.1:8545/",
      chainId: 31337,
    },
  },
  solidity: {
    version: "0.8.20", // your version of Solidity
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
};
