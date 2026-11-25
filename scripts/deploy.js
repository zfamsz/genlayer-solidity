const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const GenLayer = await hre.ethers.deployContract("GenLayer", []);

  await GenLayer.waitForDeployment();

  console.log("GenLayer contract deployed to:", await GenLayer.getAddress());

  // Save address to .env
  const fs = require('fs');
  const envPath = ".env";
  const newLine = `CONTRACT_ADDRESS=${await GenLayer.getAddress()}\n`;
  if (!fs.existsSync(envPath)) {
    fs.writeFileSync(envPath, newLine);
  } else {
    const content = fs.readFileSync(envPath, 'utf8');
    if (!content.includes("CONTRACT_ADDRESS")) {
      fs.appendFileSync(envPath, newLine);
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});