require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20", // your version of Solidity
    settings: {
      optimizer: {
        enabled: true,
        runs: 1,
      },
    },
  },
};
