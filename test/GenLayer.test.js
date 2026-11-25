const { expect } = require("chai");
const { ethers } = require("hardhat");

// Tests for the final GenLayer.sol (Solidity ^0.8.24, OpenZeppelin v5):
//   - constructor takes NO arguments (ERC721 "GenLayer" / "GLAYER")
//   - mintLayer(bytes32 inputHash, DataType dataType, uint256 complexity, string metadataURI) payable
//   - DataType enum: IKLIM=0, SUHU=1, CUACA=2, CUSTOM=3
//   - fee = baseFee + (complexity * feePerUnit * multiplier) / 100
describe("GenLayer", function () {
  let GenLayer, deployer, user1;
  const IKLIM = 0;
  const SUHU = 1;
  const CUACA = 2;
  const CUSTOM = 3;

  beforeEach(async function () {
    [deployer, user1] = await ethers.getSigners();
    const GenLayerFactory = await ethers.getContractFactory("GenLayer");
    GenLayer = await GenLayerFactory.deploy();
    await GenLayer.waitForDeployment();
  });

  it("should mint a new layer with valid input", async function () {
    const inputHash = ethers.keccak256(ethers.toUtf8Bytes("weather-2026-11-26"));
    const metadataURI = "ipfs://bafyexample/1.json";
    const complexity = 10;
    const fee = await GenLayer.calculateFee(CUACA, complexity);

    await expect(GenLayer.mintLayer(inputHash, CUACA, complexity, metadataURI, { value: fee }))
      .to.emit(GenLayer, "LayerMinted");

    const layer = await GenLayer.getLayer(1);
    expect(layer.creator).to.equal(deployer.address);
    expect(layer.inputHash).to.equal(inputHash);
    expect(layer.complexity).to.equal(complexity);
    expect(layer.metadataURI).to.equal(metadataURI);
    expect(await GenLayer.totalLayers()).to.equal(1);
    expect(await GenLayer.verifyLayer(1, inputHash)).to.equal(true);
  });

  it("should revert if input hash is zero", async function () {
    const fee = await GenLayer.calculateFee(CUACA, 10);
    await expect(
      GenLayer.mintLayer(ethers.ZeroHash, CUACA, 10, "ipfs://x", { value: fee })
    ).to.be.revertedWith("GenLayer: hash input kosong");
  });

  it("should revert if hash is already used", async function () {
    const inputHash = ethers.keccak256(ethers.toUtf8Bytes("dup"));
    const fee = await GenLayer.calculateFee(CUACA, 10);
    await GenLayer.mintLayer(inputHash, CUACA, 10, "ipfs://x", { value: fee });
    await expect(
      GenLayer.mintLayer(inputHash, CUACA, 10, "ipfs://x", { value: fee })
    ).to.be.revertedWith("GenLayer: hash sudah dipakai");
  });

  it("should revert if fee is too low", async function () {
    const inputHash = ethers.keccak256(ethers.toUtf8Bytes("lowfee"));
    await expect(
      GenLayer.mintLayer(inputHash, CUACA, 10, "ipfs://x", { value: 0 })
    ).to.be.revertedWith("GenLayer: fee kurang");
  });

  it("should revert if complexity is out of range", async function () {
    const inputHash = ethers.keccak256(ethers.toUtf8Bytes("range"));
    const fee = await GenLayer.calculateFee(CUACA, 10);
    await expect(
      GenLayer.mintLayer(inputHash, CUACA, 0, "ipfs://x", { value: fee })
    ).to.be.revertedWith("GenLayer: kompleksitas harus 1-100");
    await expect(
      GenLayer.mintLayer(inputHash, CUACA, 101, "ipfs://x", { value: fee })
    ).to.be.revertedWith("GenLayer: kompleksitas harus 1-100");
  });

  it("should calculate the correct dynamic fee", async function () {
    // CUACA, complexity 10: 0.001 + (10 * 0.0001 * 120) / 100 = 0.0022 ether
    const fee = await GenLayer.calculateFee(CUACA, 10);
    expect(fee).to.equal(ethers.parseEther("0.0022"));
    // CUSTOM, complexity 100: 0.001 + (100 * 0.0001 * 150) / 100 = 0.016 ether
    const feeMax = await GenLayer.calculateFee(CUSTOM, 100);
    expect(feeMax).to.equal(ethers.parseEther("0.016"));
    // IKLIM, complexity 1: 0.001 + (1 * 0.0001 * 100) / 100 = 0.0011 ether
    const feeMin = await GenLayer.calculateFee(IKLIM, 1);
    expect(feeMin).to.equal(ethers.parseEther("0.0011"));
  });

  it("should allow owner to update metadata without breaking verification", async function () {
    const inputHash = ethers.keccak256(ethers.toUtf8Bytes("meta"));
    const fee = await GenLayer.calculateFee(CUACA, 10);
    await GenLayer.mintLayer(inputHash, CUACA, 10, "ipfs://old", { value: fee });

    await expect(GenLayer.updateMetadata(1, "ipfs://new"))
      .to.emit(GenLayer, "MetadataUpdated")
      .withArgs(1, deployer.address, "ipfs://new");

    const layer = await GenLayer.getLayer(1);
    expect(layer.metadataURI).to.equal("ipfs://new");
    // verification still holds after metadata update
    expect(await GenLayer.verifyLayer(1, inputHash)).to.equal(true);
  });

  it("should revert if non-owner tries to update metadata", async function () {
    const inputHash = ethers.keccak256(ethers.toUtf8Bytes("meta2"));
    const fee = await GenLayer.calculateFee(CUACA, 10);
    await GenLayer.mintLayer(inputHash, CUACA, 10, "ipfs://old", { value: fee });
    await expect(GenLayer.connect(user1).updateMetadata(1, "ipfs://new"))
      .to.be.revertedWith("GenLayer: bukan pemilik layer");
  });

  it("should let owner withdraw collected fees", async function () {
    const inputHash = ethers.keccak256(ethers.toUtf8Bytes("wd"));
    const fee = await GenLayer.calculateFee(CUACA, 10);
    await GenLayer.mintLayer(inputHash, CUACA, 10, "ipfs://x", { value: fee });
    await expect(GenLayer.withdrawFees()).to.emit(GenLayer, "FeesWithdrawn");
  });

  it("should let owner update fee config", async function () {
    await GenLayer.setBaseFee(ethers.parseEther("0.002"));
    expect(await GenLayer.baseFee()).to.equal(ethers.parseEther("0.002"));
    await GenLayer.setFeePerUnit(ethers.parseEther("0.0002"));
    expect(await GenLayer.feePerUnit()).to.equal(ethers.parseEther("0.0002"));
  });

  it("should revert if non-owner sets fee config", async function () {
    await expect(GenLayer.connect(user1).setBaseFee(ethers.parseEther("0.002")))
      .to.be.revertedWithCustomError(GenLayer, "OwnableUnauthorizedAccount");
  });
});
