// Import the necessary dependencies from chai and ethers
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { arrayify } = require("@ethersproject/bytes");

describe("RockPaperScissorsGame Contract", function () {
  let RockPaperScissorsGame;
  let rps;
  let owner, player1, player2, addr1;
  let gameId;
  let stakeAmount = ethers.parseEther("1"); // 1 ETH

  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    RockPaperScissorsGame = await ethers.getContractFactory(
      "RockPaperScissorsGame"
    );
    [owner, player1, player2, addr1] = await ethers.getSigners();

    // Deploy the contract with serverPublicKey set as the owner address
    rps = await RockPaperScissorsGame.deploy(owner.address);
    await rps.waitForDeployment();
    console.log(rps.target);

    gameId = ethers.keccak256(ethers.toUtf8Bytes("game1"));
  });

  describe("Game Creation", function () {
    it("Should allow a player to create a new game", async function () {
      await expect(
        rps
          .connect(player1)
          .enterGame(
            gameId,
            stakeAmount,
            ethers.ZeroAddress,
            3,
            player2.address,
            { value: stakeAmount }
          )
      )
        .to.emit(rps, "GameCreated")
        .withArgs(gameId, player1.address, stakeAmount, ethers.ZeroAddress, 3);

      const game = await rps.games(gameId);
      expect(game.player1).to.equal(player1.address);
      expect(game.player2).to.equal(player2.address);
      expect(game.stakeAmount).to.equal(stakeAmount);
      expect(game.state).to.equal(0); // Waiting state
    });

    it("Should revert if game already exists", async function () {
      await rps
        .connect(player1)
        .enterGame(
          gameId,
          stakeAmount,
          ethers.ZeroAddress,
          3,
          player2.address,
          { value: stakeAmount }
        );
      await expect(
        rps
          .connect(player1)
          .enterGame(
            gameId,
            stakeAmount,
            ethers.ZeroAddress,
            3,
            player2.address,
            { value: stakeAmount }
          )
      ).to.be.revertedWith("Game already exists");
    });
  });

  describe("Game Joining", function () {
    it("Should allow player 2 to join the game", async function () {
      await rps
        .connect(player1)
        .enterGame(
          gameId,
          stakeAmount,
          ethers.ZeroAddress,
          3,
          player2.address,
          { value: stakeAmount }
        );

      await expect(
        rps.connect(player2).joinGame(gameId, { value: stakeAmount })
      )
        .to.emit(rps, "GameJoined")
        .withArgs(gameId, player2.address);

      const game = await rps.games(gameId);
      expect(game.state).to.equal(1); // InProgress state
    });

    it("Should revert if incorrect stake amount is sent", async function () {
      await rps
        .connect(player1)
        .enterGame(
          gameId,
          stakeAmount,
          ethers.ZeroAddress,
          3,
          player2.address,
          { value: stakeAmount }
        );

      await expect(
        rps
          .connect(player2)
          .joinGame(gameId, { value: ethers.parseEther("0.5") })
      ).to.be.revertedWith("Incorrect ETH amount sent");
    });

    it("Should revert if a non-designated player tries to join", async function () {
      await rps
        .connect(player1)
        .enterGame(
          gameId,
          stakeAmount,
          ethers.ZeroAddress,
          3,
          player2.address,
          { value: stakeAmount }
        );

      await expect(
        rps.connect(addr1).joinGame(gameId, { value: stakeAmount })
      ).to.be.revertedWith("You cannot join this game");
    });
  });

  describe("Game Completion", function () {
    it("Should submit the game result", async function () {
      // Step 1: Create and join the game
      await rps
        .connect(player1)
        .enterGame(
          gameId,
          stakeAmount,
          ethers.ZeroAddress,
          3,
          player2.address,
          { value: stakeAmount }
        );
      await rps.connect(player2).joinGame(gameId, { value: stakeAmount });

      const player1Wins = 2;
      const player2Wins = 1;
      const winner = player1.address;

      // Step 2: Compute the game hash using ethers.utils.solidityPacked to match Solidity's abi.encodePacked
      const gameHash = ethers.keccak256(
        ethers.solidityPacked(
          ["bytes32", "uint8", "uint8", "address"],
          [gameId, player1Wins, player2Wins, winner]
        )
      );

      // Step 4: Owner (serverPublicKey) signs the prefixed hash off-chain
      const signature = await owner.signMessage(arrayify(gameHash)); // Owner signs the prefixed hash

      // Step 5: Owner submits the result to the contract
      await expect(
        rps
          .connect(owner)
          .submitGameResult(
            gameId,
            winner,
            player1Wins,
            gameHash,
            signature,
            player2Wins
          )
      )
        .to.emit(rps, "GameResultSubmitted")
        .withArgs(gameId, winner);

      // Step 6: Verify game state
      const game = await rps.games(gameId);
      expect(game.state).to.equal(2); // Completed state
      expect(game.winner).to.equal(winner);
    });
  });

  describe("Game Dispute", function () {
    it("Should raise a dispute", async function () {
      await rps
        .connect(player1)
        .enterGame(
          gameId,
          stakeAmount,
          ethers.ZeroAddress,
          3,
          player2.address,
          { value: stakeAmount }
        );
      await rps.connect(player2).joinGame(gameId, { value: stakeAmount });

      const player1Wins = 2;
      const player2Wins = 1;
      const winner = player1.address;

      // Compute the game hash
      const gameHash = ethers.keccak256(
        ethers.solidityPacked(
          ["bytes32", "uint8", "uint8", "address"],
          [gameId, player1Wins, player2Wins, winner]
        )
      );

      // Owner signs the prefixed hash
      const signature = await owner.signMessage(arrayify(gameHash));

      // Owner submits the result
      await expect(
        rps
          .connect(owner)
          .submitGameResult(
            gameId,
            winner,
            player1Wins,
            gameHash,
            signature,
            player2Wins
          )
      )
        .to.emit(rps, "GameResultSubmitted")
        .withArgs(gameId, winner);

      // Player 2 raises a dispute
      await expect(rps.connect(player2).raiseDispute(gameId))
        .to.emit(rps, "DisputeRaised")
        .withArgs(gameId, player2.address);

      const game = await rps.games(gameId);
      expect(game.state).to.equal(3); // Dispute state
    });
  });

  describe("Ownership and Admin", function () {
    it("Should allow the owner to transfer ownership", async function () {
      await rps.transferOwnership(addr1.address);
      expect(await rps.owner()).to.equal(addr1.address);
    });

    it("Should allow the owner to update the server's public key", async function () {
      await rps.setServerPublicKey(addr1.address);
      expect(await rps.serverPublicKey()).to.equal(addr1.address);
    });
  });
});
