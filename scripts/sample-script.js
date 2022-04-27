// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const Greeter = await hre.ethers.getContractFactory("WANNABENFT");
  //const greeter = await Greeter.deploy('0xb0897686c545045aFc77CF20eC7A532E3120E0F1', '0x3d2341ADb2D31f1c5530cDC622016af293177AE0', '0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da');
  const greeter = await Greeter.deploy('0x01BE23585060835E02B77ef475b0Cc51aA1e0709', '0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B', '0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311');
  await greeter.deployed();

  console.log("Greeter deployed to:", greeter.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
