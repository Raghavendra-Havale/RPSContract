// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./AdminUtilities.sol";

abstract contract GameManagement is ReentrancyGuard, Pausable, AdminUtilities {
    using SafeERC20 for IERC20;

    enum GameState {
        Waiting,
        InProgress,
        Completed,
        Dispute,
        Cancelled,
        Settled
    }

    struct Game {
        address player1;
        address player2;
        uint256 stakeAmount;
        address tokenAddress;
        GameState state;
        uint256 numberOfTurns;
        uint8[2][] choices;
        uint256 lastActionTime;
        address winner;
        bool player1Dispute;
        bool player2Dispute;
    }

    mapping(uint256 => Game) public games;
    uint256 public gameCounter;

    event GameCreated(
        uint256 indexed gameId,
        address indexed player1,
        uint256 stakeAmount,
        address tokenAddress,
        uint256 numberOfTurns
    );
    event GameJoined(uint256 indexed gameId, address indexed player2);
    event GameResultSubmitted(uint256 indexed gameId, address indexed winner);
    event GameCancelled(uint256 indexed gameId);
    event GameSettled(uint256 indexed gameId, address indexed winner);
    event DisputeRaised(uint256 indexed gameId, address indexed player);

    modifier onlyPlayers(uint256 gameId) {
        require(
            msg.sender == games[gameId].player1 ||
                msg.sender == games[gameId].player2,
            "Only players involved in the game can call this"
        );
        _;
    }

    function createGame(
        uint256 stakeAmount,
        address tokenAddress,
        uint256 numberOfTurns
    ) external payable whenNotPaused nonReentrant {
        require(stakeAmount > 0, "Stake amount must be greater than zero");
        require(numberOfTurns > 0 && numberOfTurns % 2 == 1, "Invalid turns");

        if (tokenAddress == address(0)) {
            require(msg.value == stakeAmount, "Incorrect ETH amount sent");
        } else {
            require(allowedTokens[tokenAddress] != 0, "Token not allowed");
            require(
                stakeAmount >= allowedTokens[tokenAddress],
                "Stake amount too low"
            );
            IERC20(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                stakeAmount
            );
        }

        uint256 gameId = gameCounter;
        gameCounter++;
        uint8[2][] memory initialChoices = new uint8[2][](numberOfTurns);

        for (uint256 i = 0; i < numberOfTurns; i++) {
            initialChoices[i] = [3, 3];
        }

        games[gameId] = Game({
            player1: msg.sender,
            player2: address(0),
            stakeAmount: stakeAmount,
            tokenAddress: tokenAddress,
            state: GameState.Waiting,
            numberOfTurns: numberOfTurns,
            lastActionTime: block.timestamp,
            winner: address(0),
            player1Dispute: false,
            player2Dispute: false,
            choices: initialChoices
        });

        emit GameCreated(
            gameId,
            msg.sender,
            stakeAmount,
            tokenAddress,
            numberOfTurns
        );
    }

    function joinGame(
        uint256 gameId
    ) external payable whenNotPaused nonReentrant {
        Game storage game = games[gameId];
        require(game.player1 != address(0), "Game does not exist");
        require(game.state == GameState.Waiting, "Game not available to join");

        if (game.tokenAddress == address(0)) {
            require(msg.value == game.stakeAmount, "Incorrect ETH amount sent");
        } else {
            IERC20(game.tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                game.stakeAmount
            );
        }

        game.player2 = msg.sender;
        game.state = GameState.InProgress;
        game.lastActionTime = block.timestamp;

        emit GameJoined(gameId, msg.sender);
    }

    function cancelGame(
        uint256 gameId
    ) external onlyPlayers(gameId) whenNotPaused nonReentrant {
        Game storage game = games[gameId];
        require(
            game.state == GameState.InProgress ||
                game.state == GameState.Dispute,
            "Game must be in progress or in dispute to cancel"
        );

        if (msg.sender == game.player1) {
            require(!game.player1Dispute, "Player1 already agreed to cancel");
            game.player1Dispute = true;
        } else if (msg.sender == game.player2) {
            require(!game.player2Dispute, "Player2 already agreed to cancel");
            game.player2Dispute = true;
        }

        if (game.player1Dispute && game.player2Dispute) {
            // handle stake refunds to both players here
            emit GameCancelled(gameId);
        }
    }
}
