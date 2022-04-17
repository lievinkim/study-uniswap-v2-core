const { ethers } = require("hardhat");

const CONTRACT = {
  UniswapV2ERC20: "0x93bA337780F3cDD83Ec2A69Ea8969D9A07B259eC",
  UniswapV2Factory: "0xFc801cF6189C59Da80BaD090565C345355D06Cb6",
  UniswapV2Pair: "0x82c3014529E0F3F027E8f46Cd34f6CC1B53f6f8f",
};

const TOKEN = {
  LINK: "0x01BE23585060835E02B77ef475b0Cc51aA1e0709",
  TEST: "0xea19D1882F776bFa9b8a6B6Ef0e02e560363A066",
};

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account: " + deployer.address);

  const uniswapV2Factory = await ethers.getContractAt(
    "UniswapV2Factory",
    CONTRACT.UniswapV2Factory,
    deployer
  );

  console.log("uniswapV2Factory :", uniswapV2Factory.address);

  const allPairsLength = await uniswapV2Factory.allPairsLength();
  console.log(allPairsLength);

  // await uniswapV2Factory.createPair(TOKEN.LINK, TOKEN.TEST);
  // console.log("completed");

  // const TestERC20 = await ethers.getContractFactory("TestERC20");
  // const testERC20 = await TestERC20.deploy("Test Token", "TTK", "100000000");
  // await testERC20.deployed();

  // console.log("TestERC20 deployed to:", testERC20.address);

  // const UniswapV2ERC20 = await ethers.getContractFactory("UniswapV2ERC20");
  // const uniswapV2ERC20 = await UniswapV2ERC20.deploy();
  // await uniswapV2ERC20.deployed();

  // console.log("UniswapV2ERC20 deployed to:", uniswapV2ERC20.address);

  // const UniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
  // const uniswapV2Factory = await UniswapV2Factory.deploy(deployer.address);
  // await uniswapV2Factory.deployed();

  // console.log("UniswapV2Factory deployed to:", uniswapV2Factory.address);

  // const UniswapV2Pair = await ethers.getContractFactory("UniswapV2Pair");
  // const uniswapV2Pair = await UniswapV2Pair.deploy();
  // await uniswapV2Pair.deployed();

  // console.log("UniswapV2Pair deployed to:", uniswapV2Pair.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
