const { expect } = require("chai");
const { ethers } = require("hardhat");
const { arrayify } = require("@ethersproject/bytes");

describe("RockPaperScissorsGame Contract", function () {
  let RockPaperScissorsGame;
  let rockPaperScissors;
  let owner;
  let player1;
  let player2;
  let player3;
  let player4;
  let token;
  let tournamentOwner;
  const stakeAmount = ethers.parseEther("1");

  beforeEach(async function () {
    // Deploy mock ERC20 token
    const Token = await ethers.getContractFactory("ERC20Mock");
    token = await Token.deploy(
      "MockToken",
      "MTK",
      BigInt(1000000000 * 10 ** 18)
    );
    await token.waitForDeployment();
    tokenAddress = token.target;

    // Get signers
    [owner, player1, player2, player3, player4, tournamentOwner] =
      await ethers.getSigners();

    // Deploy the game contract
    RockPaperScissorsGame = await ethers.getContractFactory(
      "RockPaperScissorsGame"
    );
    rockPaperScissors = await RockPaperScissorsGame.deploy(owner.address);
    await rockPaperScissors.waitForDeployment();
    rockPaperScissorsAddress = rockPaperScissors.target;

    // Allow token for the game
    await rockPaperScissors
      .connect(owner)
      .allowToken(token.target, stakeAmount);
  });

  it("Should create a new game successfully", async function () {
    const turns = 3;
    await token.connect(player1).mint(player1.address, stakeAmount);
    await token.connect(player1).approve(rockPaperScissorsAddress, stakeAmount);
    await expect(
      rockPaperScissors
        .connect(player1)
        .createGame(stakeAmount, tokenAddress, turns)
    )
      .to.emit(rockPaperScissors, "GameCreated")
      .withArgs(1, player1.address, stakeAmount, tokenAddress, turns);

    const game = await rockPaperScissors.games(1);
    expect(game.player1).to.equal(player1.address);
    expect(game.stakeAmount).to.equal(stakeAmount);
  });

  it("Should allow player2 to join the game", async function () {
    const turns = 3;
    await token.connect(player1).mint(player1.address, stakeAmount);
    await token.connect(player1).approve(rockPaperScissorsAddress, stakeAmount);
    await rockPaperScissors
      .connect(player1)
      .createGame(stakeAmount, tokenAddress, turns);

    await token.connect(player2).mint(player2.address, stakeAmount);
    await token.connect(player2).approve(rockPaperScissorsAddress, stakeAmount);
    await expect(rockPaperScissors.connect(player2).joinGame(1))
      .to.emit(rockPaperScissors, "GameJoined")
      .withArgs(1, player2.address);

    const game = await rockPaperScissors.games(1);
    expect(game.state).to.equal(1); // InProgress
  });

  it("Should allow the game to be canceled by both players", async function () {
    const turns = 3;
    await token.connect(player1).mint(player1.address, stakeAmount);
    await token.connect(player1).approve(rockPaperScissorsAddress, stakeAmount);
    await rockPaperScissors
      .connect(player1)
      .createGame(stakeAmount, tokenAddress, turns);
    await token.connect(player2).mint(player2.address, stakeAmount);
    await token.connect(player2).approve(rockPaperScissorsAddress, stakeAmount);
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
    await token.connect(player1).mint(player1.address, stakeAmount);
    await token.connect(player1).approve(rockPaperScissorsAddress, stakeAmount);
    await rockPaperScissors
      .connect(player1)
      .createGame(stakeAmount, tokenAddress, turns);
    await token.connect(player2).mint(player2.address, stakeAmount);
    await token.connect(player2).approve(rockPaperScissorsAddress, stakeAmount);
    await rockPaperScissors.connect(player2).joinGame(1);

    const player1Wins = 2;
    const player2Wins = 1;
    const winner = player1.address;

    const gameChoices = [
      [0, 1],
      [1, 2],
      [2, 0],
    ];

    // Simulate the game completion
    await rockPaperScissors.submitGameResult(1, player1.address, gameChoices);

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
    const player2s = [player3.address, player4.address];
    const numberOfTurnsList = [turns, turns];
    const tournamentAddress = "0x860f986606e75057836BDb7f3214f098f4e6C969";
    await rockPaperScissors
      .connect(owner)
      .addTournamentOwner(tournamentOwner, tournamentAddress);

    await expect(
      rockPaperScissors
        .connect(tournamentOwner)
        .createTournamentGames(
          player1s,
          player2s,
          numberOfTurnsList,
          tournamentAddress
        )
    )
      .to.emit(rockPaperScissors, "TournamentGameCreated")
      .withArgs(1, player1.address, player3.address, turns, tournamentAddress);

    const gameChoices = [
      [0, 1],
      [1, 2],
      [2, 0],
    ];
    const winner = player1.address;

    // Simulate result submission
    await expect(
      rockPaperScissors.SubmitAndApproveTournamentGame(1, winner, gameChoices)
    )
      .to.emit(rockPaperScissors, "TournamentGameResultSubmitted")
      .withArgs(1, player1.address);
  });

  it("Should approve the winner and transfer funds with protocol fee deduction", async function () {
    const turns = 3;

    // Mint and approve tokens for player1
    await token.connect(player1).mint(player1.address, stakeAmount);
    await token.connect(player1).approve(rockPaperScissorsAddress, stakeAmount);

    // Player1 creates a game
    await rockPaperScissors
      .connect(player1)
      .createGame(stakeAmount, tokenAddress, turns);

    // Mint and approve tokens for player2
    await token.connect(player2).mint(player2.address, stakeAmount);
    await token.connect(player2).approve(rockPaperScissorsAddress, stakeAmount);

    // Player2 joins the game
    await rockPaperScissors.connect(player2).joinGame(1);

    const gameChoices = [
      [0, 1],
      [1, 2],
      [2, 0],
    ];
    const winner = player1.address;

    // Simulate the game completion
    await rockPaperScissors.submitGameResult(1, player1.address, gameChoices);

    await rockPaperScissors.connect(owner).updateDisputePeriod(0);

    // Owner approves the winner
    await expect(rockPaperScissors.connect(owner).approveWinner(1))
      .to.emit(rockPaperScissors, "GameSettled")
      .withArgs(1, player1.address);

    // Check the winner's pending balance after protocol fee deduction
    const totalStake = stakeAmount * BigInt(2);
    const protocolFee =
      (totalStake * BigInt(await rockPaperScissors.protocolFee())) /
      BigInt(await rockPaperScissors.FEE_DENOMINATOR());
    const amountAfterFee = totalStake - protocolFee;

    expect(await token.balanceOf(player1.address)).to.equal(amountAfterFee);
  });

  it("Should resolve a dispute and transfer funds based on dispute result", async function () {
    const turns = 3;

    // Player1 and Player2 create and join the game
    await token.connect(player1).mint(player1.address, stakeAmount);
    await token.connect(player1).approve(rockPaperScissorsAddress, stakeAmount);
    await rockPaperScissors
      .connect(player1)
      .createGame(stakeAmount, tokenAddress, turns);

    await token.connect(player2).mint(player2.address, stakeAmount);
    await token.connect(player2).approve(rockPaperScissorsAddress, stakeAmount);
    await rockPaperScissors.connect(player2).joinGame(1);

    const gameChoices = [
      [0, 1],
      [1, 2],
      [2, 0],
    ];
    const winner = player1.address;

    // Simulate the game completion
    await rockPaperScissors.submitGameResult(1, player1.address, gameChoices);

    // Player2 raises a dispute
    await rockPaperScissors.connect(player2).raiseDispute(1);

    // Admin resolves the dispute in favor of player2 (disputeId = 2)
    await expect(rockPaperScissors.connect(owner).resolveDispute(1, 2))
      .to.emit(rockPaperScissors, "GameSettled")
      .withArgs(1, player2.address);

    // Check that player2 received the funds
    const totalStake = stakeAmount * BigInt(2);
    const protocolFee =
      (totalStake * (await rockPaperScissors.protocolFee())) /
      (await rockPaperScissors.FEE_DENOMINATOR());
    const amountAfterFee = totalStake - protocolFee;

    expect(await token.balanceOf(player2.address)).to.equal(amountAfterFee);
  });

  it("Should allow the creator to cancel an unstarted game", async function () {
    // Player1 creates a game but no one joins
    await token.connect(player1).mint(player1.address, stakeAmount);
    await token.connect(player1).approve(rockPaperScissorsAddress, stakeAmount);
    await rockPaperScissors
      .connect(player1)
      .createGame(stakeAmount, tokenAddress, 3);

    // Simulate passing of game expiration time
    await ethers.provider.send("evm_increaseTime", [25 * 60 * 60]); // Increase time by 25 hours
    await ethers.provider.send("evm_mine");

    // Player1 cancels the unstarted game
    await expect(rockPaperScissors.connect(player1).cancelUnstartedGame(1))
      .to.emit(rockPaperScissors, "GameCancelled")
      .withArgs(1);

    // Check that player1 received the stake amount back
    expect(await token.balanceOf(player1.address)).to.equal(stakeAmount);
  });

  it("Should return correct player stats after multiple games", async function () {
    const turns = 3;

    // Player1 and Player2 create and join multiple games
    await token.connect(player1).mint(player1.address, stakeAmount * BigInt(2));
    await token
      .connect(player1)
      .approve(rockPaperScissorsAddress, stakeAmount * BigInt(2));
    await rockPaperScissors
      .connect(player1)
      .createGame(stakeAmount, tokenAddress, turns);
    await rockPaperScissors
      .connect(player1)
      .createGame(stakeAmount, tokenAddress, turns);

    await token.connect(player2).mint(player2.address, stakeAmount * BigInt(2));
    await token
      .connect(player2)
      .approve(rockPaperScissorsAddress, stakeAmount * BigInt(2));
    await rockPaperScissors.connect(player2).joinGame(1);
    await rockPaperScissors.connect(player2).joinGame(2);

    // Fetch player stats
    const player1Stats = await rockPaperScissors.getPlayerStats(
      player1.address
    );
    const player2Stats = await rockPaperScissors.getPlayerStats(
      player2.address
    );

    expect(player1Stats.gamesPlayed).to.equal(2);
    expect(player2Stats.gamesPlayed).to.equal(2);
  });

  it("Should create, join, and approve games with ETH", async function () {
    const stakeAmountETH = ethers.parseEther("1");
    const turns = 3;

    // Player1 creates a game with ETH
    await expect(
      rockPaperScissors
        .connect(player1)
        .createGame(stakeAmountETH, ethers.ZeroAddress, turns, {
          value: stakeAmountETH,
        })
    )
      .to.emit(rockPaperScissors, "GameCreated")
      .withArgs(1, player1.address, stakeAmountETH, ethers.ZeroAddress, turns);

    // Player2 joins the game with ETH
    await expect(
      rockPaperScissors.connect(player2).joinGame(1, { value: stakeAmountETH })
    )
      .to.emit(rockPaperScissors, "GameJoined")
      .withArgs(1, player2.address);

    const gameChoices = [
      [0, 1],
      [1, 2],
      [2, 0],
    ];
    const winner = player1.address;

    // Simulate the game completion
    await rockPaperScissors.submitGameResult(1, player1.address, gameChoices);

    await ethers.provider.send("evm_increaseTime", [60 * 61]); // Increase time by 61 minutes
    await ethers.provider.send("evm_mine");

    const player1BalanceBefore = await ethers.provider.getBalance(
      player1.address
    );

    // Approve the game result and transfer ETH to the winner
    await rockPaperScissors.connect(owner).approveWinner(1);

    const player1BalanceAfter = await ethers.provider.getBalance(
      player1.address
    );

    const rewardReceived = player1BalanceAfter - player1BalanceBefore;

    const protocolFee =
      (stakeAmountETH * BigInt(2) * (await rockPaperScissors.protocolFee())) /
      (await rockPaperScissors.FEE_DENOMINATOR());
    const amountAfterFee = stakeAmountETH * BigInt(2) - protocolFee;

    expect(rewardReceived).to.equal(amountAfterFee);
  });
});
