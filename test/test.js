const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RockPaperScissorsGame Contract", function () {
  let RockPaperScissorsGame;
  let rockPaperScissors;
  let owner;
  let player1;
  let player2;
  let player3;
  let token;
  const stakeAmount = ethers.parseEther("1");

  beforeEach(async function () {
    // Deploy mock ERC20 token
    const Token = await ethers.getContractFactory("ERC20Mock");
    token = await Token.deploy("MockToken", "MTK", stakeAmount * 100);
    await token.deployed();

    // Get signers
    [owner, player1, player2, player3] = await ethers.getSigners();

    // Deploy the game contract
    RockPaperScissorsGame = await ethers.getContractFactory(
      "RockPaperScissorsGame"
    );
    rockPaperScissors = await RockPaperScissorsGame.deploy(owner.address);
    await rockPaperScissors.deployed();

    // Allow token for the game
    await rockPaperScissors.allowToken(token.address, stakeAmount);
  });

  it("Should create a new game successfully", async function () {
    const turns = 3;
    await token
      .connect(player1)
      .approve(rockPaperScissors.address, stakeAmount);
    await expect(
      rockPaperScissors
        .connect(player1)
        .createGame(stakeAmount, token.address, turns, player2.address)
    )
      .to.emit(rockPaperScissors, "GameCreated")
      .withArgs(1, player1.address, stakeAmount, token.address, turns);

    const game = await rockPaperScissors.games(1);
    expect(game.player1).to.equal(player1.address);
    expect(game.player2).to.equal(player2.address);
    expect(game.stakeAmount).to.equal(stakeAmount);
  });

  it("Should allow player2 to join the game", async function () {
    const turns = 3;
    await token
      .connect(player1)
      .approve(rockPaperScissors.address, stakeAmount);
    await rockPaperScissors
      .connect(player1)
      .createGame(stakeAmount, token.address, turns, player2.address);

    await token
      .connect(player2)
      .approve(rockPaperScissors.address, stakeAmount);
    await expect(rockPaperScissors.connect(player2).joinGame(1))
      .to.emit(rockPaperScissors, "GameJoined")
      .withArgs(1, player2.address);

    const game = await rockPaperScissors.games(1);
    expect(game.state).to.equal(1); // InProgress
  });

  it("Should allow the game to be canceled by both players", async function () {
    const turns = 3;
    await token
      .connect(player1)
      .approve(rockPaperScissors.address, stakeAmount);
    await rockPaperScissors
      .connect(player1)
      .createGame(stakeAmount, token.address, turns, player2.address);

    await token
      .connect(player2)
      .approve(rockPaperScissors.address, stakeAmount);
    await rockPaperScissors.connect(player2).joinGame(1);

    await expect(rockPaperScissors.connect(player1).cancelByAgreement(1)).to.not
      .be.reverted;
    await expect(rockPaperScissors.connect(player2).cancelByAgreement(1))
      .to.emit(rockPaperScissors, "GameCancelled")
      .withArgs(1);

    const game = await rockPaperScissors.games(1);
    expect(game.state).to.equal(4); // Cancelled
  });

  it("Should raise a dispute", async function () {
    const turns = 3;
    await token
      .connect(player1)
      .approve(rockPaperScissors.address, stakeAmount);
    await rockPaperScissors
      .connect(player1)
      .createGame(stakeAmount, token.address, turns, player2.address);

    await token
      .connect(player2)
      .approve(rockPaperScissors.address, stakeAmount);
    await rockPaperScissors.connect(player2).joinGame(1);

    // Simulate the game completion
    await rockPaperScissors.submitGameResult(
      1,
      player1.address,
      2,
      1,
      [
        [0, 1],
        [1, 2],
        [2, 0],
      ],
      ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test")),
      "0x"
    );

    // Player2 raises a dispute
    await expect(rockPaperScissors.connect(player2).raiseDispute(1))
      .to.emit(rockPaperScissors, "DisputeRaised")
      .withArgs(1, player2.address);

    const game = await rockPaperScissors.games(1);
    expect(game.state).to.equal(3); // Dispute
  });

  it("Should handle a winner for a tournament game", async function () {
    const turns = 3;

    const player1s = [player1.address, player2.address];
    const player2s = [player2.address, player3.address];
    const numberOfTurnsList = [turns, turns];

    await expect(
      rockPaperScissors
        .connect(owner)
        .createTournamentGames(
          player1s,
          player2s,
          numberOfTurnsList,
          owner.address
        )
    )
      .to.emit(rockPaperScissors, "TournamentGameCreated")
      .withArgs(1, player1.address, player2.address, turns, owner.address);

    // Simulate result submission
    await rockPaperScissors.submitGameResult(
      1,
      player1.address,
      2,
      1,
      [
        [0, 1],
        [1, 2],
        [2, 0],
      ],
      ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test")),
      "0x"
    );

    await expect(
      rockPaperScissors
        .connect(owner)
        .SubmitAndApproveTournamentGame(1, player1.address, 2, 1, [
          [0, 1],
          [1, 2],
          [2, 0],
        ])
    )
      .to.emit(rockPaperScissors, "TournamentGameResultSubmitted")
      .withArgs(1, player1.address);
  });

  it("Should allow players to withdraw pending amounts", async function () {
    const initialBalance = await player1.getBalance();
    await rockPaperScissors.connect(owner).withdraw();
    const finalBalance = await player1.getBalance();
    expect(finalBalance).to.be.above(initialBalance);
  });
});
