require("@nomiclabs/hardhat-waffle");
require("dotenv").config();

const chainIds = {
  hardhat: 1337,
  rinkeby: 4,
};

const privateKey = process.env.PRIVATE_KEY ?? "NO_PRIVATE_KEY";
const alchemyApiKey = process.env.ALCHEMY_API_KEY ?? "NO_ALCHEMY_API_KEY";

function getChainConfig(network) {
  const url = `https://eth-${network}.alchemyapi.io/v2/${alchemyApiKey}`;
  return {
    accounts: [`${privateKey}`],
    chainId: chainIds[network],
    url,
  };
}

module.exports = {
  defaultNetwork: "rinkeby",
  networks: {
    hardhat: {
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${alchemyApiKey}`,
      },
      chainId: chainIds.hardhat,
    },
    mainnet: getChainConfig("mainnet"),
    rinkeby: getChainConfig("rinkeby"),
  },
  solidity: {
    compilers: [
      {
        version: "0.8.10",
        settings: {
          metadata: {
            bytecodeHash: "none",
          },
          optimizer: {
            enabled: true,
            runs: 800,
          },
        },
      },
      {
        version: "0.7.5",
        settings: {
          metadata: {
            bytecodeHash: "none",
          },
          optimizer: {
            enabled: true,
            runs: 800,
          },
        },
      },
      {
        version: "0.5.16",
      },
    ],
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};
