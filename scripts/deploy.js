// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const ethers = hre.ethers;


const routers = [
    '0x10ED43C718714eb63d5aA57B78B54704E256024E',
    '0x325E343f1dE602396E256B67eFd1F61C3A6B38Bd',
    '0xcF0feBd3f17CEf5b47b0cD257aCf6025c5BFf3b7',
    '0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8',
    '0x0384E9ad329396C3A6A401243Ca71633B2bC4333'
]

const names = [
    'PancakeSwap',
    'BabySwap',
    'ApeSwap',
    'BiSwap',
    'MdexSwap'
]

const WETH = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c'; // WBNB

const bridge_tokens = [
    '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c', // WBNB
  '0xe9e7cea3dedca5984780bafc599bd69add087d56', // BUSD
    '0x55d398326f99059ff775485246999027b3197955', // USDT
    '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d', // USDC
    '0x2170Ed0880ac9A755fd29B2688956BD959F933F8', // ETH
];


async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const Router = await ethers.getContractFactory("PortifyRouter");
  const router = await Router.deploy(routers, names, WETH, bridge_tokens);

  await router.deployed();

  console.log("Router deployed to:", router.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
