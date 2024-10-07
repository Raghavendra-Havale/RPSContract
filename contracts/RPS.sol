// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RockPaperScissorsGame is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    uint256 public gameCounter;

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

    struct PlayerStats {
        uint256 gamesPlayed;
        uint256 gamesWon;
        uint256 gamesLost;
        uint256 gamesDrawn;
        uint256 gamesCancelled;
        uint256[] gameIds;
    }

    mapping(uint256 => Game) public games;
    mapping(address => uint256) public allowedTokens;
    mapping(address => PlayerStats) public playerStats;
    mapping(address => address) public tournamentOwners;

    address public serverPublicKey;
    uint256 public protocolFee = 20;
    uint256 public drawFee = 5;
    uint256 public constant FEE_DENOMINATOR = 10000;

    uint256 public disputePeriod = 1 seconds;
    uint256 public maxTurns = 7;

    event GameCreated(
        uint256 indexed gameId,
        address indexed player1,
        uint256 stakeAmount,
        address tokenAddress,
        uint256 numberOfTurns
    );
    event TournamentGameCreated(
        uint256 indexed gameId,
        address indexed player1,
        address indexed player2,
        uint256 numberOfTurns,
        address tournamentContractAddress
    );
    event GameJoined(uint256 indexed gameId, address indexed player2);
    event GameResultSubmitted(uint256 indexed gameId, address indexed winner);
    event DisputeRaised(uint256 indexed gameId, address indexed player);
    event GameCancelled(uint256 indexed gameId);
    event GameSettled(uint256 indexed gameId, address indexed winner);
    event TournamentGameResultSubmitted(
        uint256 indexed gameId,
        address indexed winner
    );

    modifier onlyPlayers(uint256 gameId) {
        require(
            msg.sender == games[gameId].player1 ||
                msg.sender == games[gameId].player2,
            "Not a player"
        );
        _;
    }

    modifier onlyTournamentOwner(address tournamentContractAddress) {
        require(
            tournamentOwners[msg.sender] == tournamentContractAddress,
            "Not tournament owner"
        );
        _;
    }

    modifier onlyOwnerOrServer() {
        require(
            msg.sender == owner() || msg.sender == serverPublicKey,
            "Not owner or server"
        );
        _;
    }

    constructor(address _serverPublicKey) Ownable(msg.sender) {
        serverPublicKey = _serverPublicKey;
        gameCounter++;
    }

    function setServerPublicKey(address newKey) external onlyOwner {
        require(newKey != address(0), "Null address");
        serverPublicKey = newKey;
    }

    function setProtocolFee(uint256 newFee) external onlyOwner {
        require(newFee <= 100, "Too high");
        protocolFee = newFee;
    }

    function setDrawFee(uint256 newFee) external onlyOwner {
        require(newFee <= 100, "Too high");
        drawFee = newFee;
    }

    function updateDisputePeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod <= 1 hours, "Too high");
        disputePeriod = newPeriod;
    }

    function allowToken(
        address tokenAddress,
        uint256 minStake
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(minStake > 0, "Minstake cannot be zero");
        allowedTokens[tokenAddress] = minStake;
    }

    function getGameDetails(
        uint256 gameId
    )
        external
        view
        returns (
            address player1,
            address player2,
            uint256 stakeAmount,
            address tokenAddress,
            uint256 numberOfTurns, // Change this to uint8 to match the type in the Game struct
            GameState state,
            uint256 lastActionTime,
            address winner
        )
    {
        Game storage game = games[gameId];
        return (
            game.player1,
            game.player2,
            game.stakeAmount,
            game.tokenAddress,
            game.numberOfTurns, // This is a uint8, so it should match the return type
            game.state,
            game.lastActionTime,
            game.winner
        );
    }

    function getAllowedTokens(
        address tokenAddress
    ) external view returns (uint256) {
        uint256 minStake = allowedTokens[tokenAddress];
        return minStake;
    }

    function addTournamentOwner(
        address _owner,
        address _tournamentContractAddress
    ) external onlyOwnerOrServer {
        require(_owner != address(0), "Invalid owner address");
        require(
            _tournamentContractAddress != address(0),
            "Invalid tournament contract address"
        );
        tournamentOwners[_owner] = _tournamentContractAddress;
    }

    function removeTournamentOwner(address _owner) external onlyOwnerOrServer {
        require(
            tournamentOwners[_owner] != address(0),
            "Not a tournament owner"
        );
        delete tournamentOwners[_owner];
    }

    function createGame(
        uint256 stakeAmount,
        address tokenAddress,
        uint256 numberOfTurns
    ) external payable whenNotPaused nonReentrant {
        require(stakeAmount > 0, "Stake amount cannot be zero");
        require(numberOfTurns > 0, "Invalid turns");

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
        updatePlayerGameStats(msg.sender, gameId);

        uint8[2][] memory initialChoices = new uint8[2][](numberOfTurns);
        for (uint256 i = 0; i < numberOfTurns; i++) {
            initialChoices[i] = [3, 3]; // 3 represents no choice made
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
        updatePlayerGameStats(msg.sender, gameId);
        game.state = GameState.InProgress;
        game.lastActionTime = block.timestamp;

        emit GameJoined(gameId, msg.sender);
    }

    function cancelByAgreement(
        uint256 gameId
    ) external whenNotPaused onlyPlayers(gameId) nonReentrant {
        Game storage game = games[gameId];
        require(
            game.state == GameState.InProgress ||
                game.state == GameState.Dispute,
            "Game state is not progress or dispute"
        );

        if (msg.sender == game.player1) {
            require(!game.player1Dispute, "Player1 already agreed to cancel");
            game.player1Dispute = true;
        } else if (msg.sender == game.player2) {
            require(!game.player2Dispute, "Player2 already agreed to cancel");
            game.player2Dispute = true;
        }

        if (game.player1Dispute && game.player2Dispute) {
            transferFunds(
                game.player1,
                address(this),
                game.stakeAmount,
                game.tokenAddress
            );
            transferFunds(
                game.player2,
                address(this),
                game.stakeAmount,
                game.tokenAddress
            );

            playerStats[game.player1].gamesCancelled++;
            playerStats[game.player2].gamesCancelled++;
            game.state = GameState.Cancelled;

            emit GameCancelled(gameId);
        }
    }

    function submitGameResult(
        uint256 gameId,
        address winner,
        uint8[2][] memory choices
    ) external whenNotPaused onlyOwnerOrServer nonReentrant {
        Game storage game = games[gameId];
        require(game.state == GameState.InProgress, "Game is not in progress");

        require(
            winner == game.player1 ||
                winner == game.player2 ||
                winner == address(0),
            "Invalid winner address"
        );

        require(
            choices.length == game.numberOfTurns,
            "Invalid number of choices"
        );

        game.choices = choices;
        game.winner = winner;
        game.state = GameState.Completed;
        game.lastActionTime = block.timestamp;
        game.player1Dispute = false;
        game.player2Dispute = false;

        emit GameResultSubmitted(gameId, winner);
    }

    function approveWinner(
        uint256 gameId
    ) external whenNotPaused onlyOwnerOrServer nonReentrant {
        Game storage game = games[gameId];
        require(game.state == GameState.Completed, "Game must be completed");
        require(
            block.timestamp > game.lastActionTime + disputePeriod,
            "Dispute window is still open"
        );

        address winner = game.winner;
        uint256 totalStake = game.stakeAmount * 2;
        _handleWinnerOrDraw(gameId, totalStake, winner);
        updatePlayerGameResultStats(gameId, winner);

        game.state = GameState.Settled;
        emit GameSettled(gameId, winner);
    }

    function raiseDispute(
        uint256 gameId
    ) external whenNotPaused onlyPlayers(gameId) nonReentrant {
        Game storage game = games[gameId];
        require(game.state == GameState.Completed, "Not a completed games");
        require(
            block.timestamp <= game.lastActionTime + disputePeriod,
            "Dispute period expired"
        );

        if (msg.sender == game.player1) {
            game.player1Dispute = true;
        } else if (msg.sender == game.player2) {
            game.player2Dispute = true;
        }

        game.state = GameState.Dispute;
        game.lastActionTime = block.timestamp;

        emit DisputeRaised(gameId, msg.sender);
    }

    function resolveDispute(
        uint256 gameId,
        uint8 disputeId
    ) external onlyOwnerOrServer whenNotPaused nonReentrant {
        Game storage game = games[gameId];
        require(game.state == GameState.Dispute, "No dispute to resolve");
        address winner = game.winner;
        uint256 totalStake = game.stakeAmount * 2;
        address otherPlayer = (game.winner == game.player1)
            ? game.player2
            : game.player1;

        if (disputeId == 0) {
            _handleWinnerOrDraw(gameId, totalStake, address(0));
            updatePlayerGameResultStats(gameId, address(0));
            emit GameSettled(gameId, address(0));
        } else if (disputeId == 1) {
            _handleWinnerOrDraw(gameId, totalStake, winner);
            updatePlayerGameResultStats(gameId, winner);
            emit GameSettled(gameId, winner);
        } else if (disputeId == 2) {
            _handleWinnerOrDraw(gameId, totalStake, otherPlayer);
            emit GameSettled(gameId, otherPlayer);
            updatePlayerGameResultStats(gameId, otherPlayer);
        } else {
            revert("Invalid dispute resolution option");
        }

        game.state = GameState.Settled;
    }

    function cancelUnstartedGame(uint256 gameId) external nonReentrant {
        Game storage game = games[gameId];
        require(
            game.player1 == msg.sender || owner() == msg.sender,
            "Not creator or admin"
        );
        require(game.state == GameState.Waiting, "Game started");
        playerStats[game.player1].gamesCancelled++;
        transferFunds(
            game.player1,
            address(this),
            game.stakeAmount,
            game.tokenAddress
        );

        emit GameCancelled(gameId);
    }

    function _handleWinnerOrDraw(
        uint256 gameId,
        uint256 totalStake,
        address winner
    ) internal {
        uint256 amountAfterFee;
        Game storage game = games[gameId];
        if (winner == address(0)) {
            amountAfterFee = amountAfterCut(totalStake / 2, drawFee);
            transferFunds(
                game.player1,
                address(this),
                amountAfterFee,
                game.tokenAddress
            );
            transferFunds(
                game.player2,
                address(this),
                amountAfterFee,
                game.tokenAddress
            );
        } else {
            amountAfterFee = amountAfterCut(totalStake, protocolFee);
            transferFunds(
                winner,
                address(this),
                amountAfterFee,
                game.tokenAddress
            );
        }
    }

    function withdrawProtocolFunds(
        address tokenAddress,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (tokenAddress == address(0)) {
            // Withdraw ETH
            require(
                address(this).balance >= amount,
                "Insufficient contract balance"
            );
            (bool success, ) = owner().call{value: amount}("");
            require(success, "ETH withdrawal failed");
        } else {
            // Withdraw ERC20 Tokens
            IERC20 token = IERC20(tokenAddress);
            uint256 tokenBalance = token.balanceOf(address(this));
            require(tokenBalance >= amount, "Insufficient token balance");
            token.safeTransfer(owner(), amount);
        }
    }

    function getPlayerStats(
        address player
    )
        external
        view
        returns (
            uint256 gamesPlayed,
            uint256 gamesWon,
            uint256 gamesLost,
            uint256 gamesDrawn,
            uint256[] memory gameIds
        )
    {
        PlayerStats storage stats = playerStats[player];

        return (
            stats.gamesPlayed,
            stats.gamesWon,
            stats.gamesLost,
            stats.gamesDrawn,
            stats.gameIds
        );
    }

    function updatePlayerGameStats(address player, uint256 gameId) internal {
        PlayerStats storage stats = playerStats[player];
        stats.gamesPlayed++;
        stats.gameIds.push(gameId);
    }

    function updatePlayerGameResultStats(
        uint256 gameId,
        address winner
    ) internal {
        Game storage game = games[gameId];
        if (winner == address(0)) {
            // Game is a draw
            playerStats[game.player1].gamesDrawn++;
            playerStats[game.player2].gamesDrawn++;
        } else if (winner == game.player1) {
            // Player1 wins
            playerStats[game.player1].gamesWon++;
            playerStats[game.player2].gamesLost++;
        } else if (winner == game.player2) {
            // Player2 wins
            playerStats[game.player2].gamesWon++;
            playerStats[game.player1].gamesLost++;
        }
    }

    function amountAfterCut(
        uint256 amount,
        uint256 cutInBasisPoints
    ) internal pure returns (uint256) {
        return amount - ((amount * cutInBasisPoints) / FEE_DENOMINATOR);
    }

    receive() external payable {
        revert("Direct ETH transfers not allowed");
    }

    function transferFunds(
        address receiver,
        address sender,
        uint256 amount,
        address tokenAddress
    ) internal {
        if (tokenAddress == address(0)) {
            (bool success, ) = receiver.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20 token = IERC20(tokenAddress);
            if (sender == address(this)) {
                token.safeTransfer(receiver, amount);
            } else {
                token.safeTransferFrom(sender, receiver, amount);
            }
        }
    }

    function createTournamentGames(
        address[] calldata player1s,
        address[] calldata player2s,
        uint256[] calldata numberOfTurnsList,
        address tournamentContractAddress
    )
        external
        onlyTournamentOwner(tournamentContractAddress)
        whenNotPaused
        nonReentrant
    {
        require(
            player1s.length == player2s.length &&
                player1s.length == numberOfTurnsList.length,
            "Input arrays length mismatch"
        );

        for (uint256 i = 0; i < player1s.length; i++) {
            require(numberOfTurnsList[i] > 0, "Invalid number of turns");

            uint256 gameId = gameCounter;
            gameCounter++;
            updatePlayerGameStats(player1s[i], gameId);
            updatePlayerGameStats(player2s[i], gameId);

            uint8[2][] memory initialChoices = new uint8[2][](
                numberOfTurnsList[i]
            );
            for (uint256 j = 0; j < numberOfTurnsList[i]; j++) {
                initialChoices[j] = [3, 3];
            }
            games[gameId] = Game({
                player1: player1s[i],
                player2: player2s[i],
                stakeAmount: 0,
                tokenAddress: address(0),
                state: GameState.InProgress,
                numberOfTurns: numberOfTurnsList[i],
                lastActionTime: block.timestamp,
                winner: address(0),
                player1Dispute: false,
                player2Dispute: false,
                choices: initialChoices
            });

            emit TournamentGameCreated(
                gameId,
                player1s[i],
                player2s[i],
                numberOfTurnsList[i],
                tournamentContractAddress
            );
        }
    }

    function SubmitAndApproveTournamentGame(
        uint256 gameId,
        address winner,
        uint8[2][] memory choices
    ) external onlyOwnerOrServer whenNotPaused nonReentrant {
        Game storage game = games[gameId];
        require(game.state == GameState.InProgress, "Game is not in progress");

        require(
            winner == game.player1 ||
                winner == game.player2 ||
                winner == address(0),
            "Invalid winner address"
        );
        require(
            choices.length == game.numberOfTurns,
            "Invalid number of choices"
        );

        game.choices = choices;
        game.winner = winner;
        game.state = GameState.Settled;
        game.lastActionTime = block.timestamp;
        updatePlayerGameResultStats(gameId, winner);
        emit TournamentGameResultSubmitted(gameId, winner);
    }
}
