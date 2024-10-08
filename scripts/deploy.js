const { ethers, run, network } = require("hardhat");

async function main() {
  const SimpleStorageFactory = await ethers.getContractFactory("RPSConnector");
  console.log("Deploying contract...");
  const owner = "0x3103Cac5ad1fC41aF7e00E0d42665d9a690574d8";
  // const tokenName = "MyToken";
  // const tokenSymbol = "MT";
  // const supply = "1000000000000000000000000000000000";
  const simpleStorage = await SimpleStorageFactory.deploy();
  const simpleStorageaddress = await simpleStorage.getAddress();
  console.log(`Deployed contract to : ${simpleStorageaddress}`);

  if (network.config.chainId === 1328 && process.env.ETHERSCAN_API_KEY) {
    await simpleStorage.deploymentTransaction(6);
    await customVerify(simpleStorageaddress, []);
  }
}

async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function customVerify(simpleStorageaddress, args) {
  console.log("Verifying...");
  await sleep(120 * 1000);
  try {
    await run("verify:verify", {
      address: simpleStorageaddress,
      constructorArguments: args,
    });
  } catch (e) {
    if (e.message.toLowerCase().includes("already verified")) {
      console.log("Already verified");
    } else {
      console.log(e);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
