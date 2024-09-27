const { version } = require("@nomicfoundation/hardhat-toolbox");

require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();

require("hardhat-gas-reporter");


task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    sepolia: {
      url: process.env.APIKEY,
      accounts: [process.env.PRIVATE_KEY]
    },
  },
  solidity: {
    compilers:[
      {version: "0.6.6"},
      {version: "0.5.16"}
    ],
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  // etherscan: {
  //   apiKey: 
  // },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 4000
  }
};
