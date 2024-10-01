// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract RockPaperScissorsGame is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private gameCounter; // For safely managing game IDs

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
        uint256 player1Wins;
        uint256 player2Wins;
        uint256 lastActionTime;
        address winner;
        uint256 creationTime;
        bool player1Dispute;
        bool player2Dispute;
    }

    struct PlayerStats {
        uint256 gamesPlayed;
        uint256 gamesWon;
        uint256 gamesLost;
        uint256 gamesDrawn;
        uint256 gamesCancelled;
        uint256[] gameIds; // To store all the game IDs a player has participated in
    }

    mapping(uint256 => Game) public games; // Mapping of game session IDs to games
    mapping(address => uint256) public pendingWithdrawals; // For handling withdrawals
    mapping(address => uint256) public allowedTokens; // Mapping for allowed tokens and their minimum stake
    mapping(address => PlayerStats) public playerStats; // Mapping for player stats
    mapping(address => address) public tournamentOwners; // ownerAddress => tournamentContractAddress

    address public serverPublicKey; // Public key of the off-chain server
    uint256 public protocolFee = 20; // 0.2% in basis points
    uint256 public drawFee = 5; // 0.05% in basis points
    uint256 public constant FEE_DENOMINATOR = 10000; // Used to calculate percentage

    uint256 public disputePeriod = 1 hours; // Configurable dispute period
    uint256 public gameExpirationTime = 24 hours; // Time after which unstarted games can be cancelled
    uint256 public maxTurns = 7; // Maximum number of turns, must be odd

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
    event Withdrawal(address indexed player, uint256 amount);
    event ServerPublicKeyUpdated(
        address indexed oldKey,
        address indexed newKey
    );
    event ProtocolFeeUpdated(uint256 newFee);
    event DrawFeeUpdated(uint256 newFee);
    event TokenAllowed(address tokenAddress, uint256 minStake);
    event TournamentGameResultSubmitted(
        uint256 indexed gameId,
        address indexed winner
    );

    modifier onlyPlayers(uint256 gameId) {
        require(
            msg.sender == games[gameId].player1 ||
                msg.sender == games[gameId].player2,
            "Only players involved in the game can call this"
        );
        _;
    }

    modifier onlyTournamentOwner(address tournamentContractAddress) {
        require(
            tournamentOwners[msg.sender] == tournamentContractAddress,
            "Caller is not the owner of the given tournament contract"
        );
        _;
    }

    constructor(address _serverPublicKey) Ownable(msg.sender) {
        serverPublicKey = _serverPublicKey;
    }

    // Admin functions
    function setServerPublicKey(address newKey) external onlyOwner {
        require(newKey != address(0), "New key is zero address");
        emit ServerPublicKeyUpdated(serverPublicKey, newKey);
        serverPublicKey = newKey;
    }

    function setProtocolFee(uint256 newFee) external onlyOwner {
        require(newFee <= 100, "Protocol fee too high");
        protocolFee = newFee;
        emit ProtocolFeeUpdated(newFee);
    }

    function setDrawFee(uint256 newFee) external onlyOwner {
        require(newFee <= 100, "Draw fee too high");
        drawFee = newFee;
        emit DrawFeeUpdated(newFee);
    }

    function allowToken(
        address tokenAddress,
        uint256 minStake
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(minStake > 0, "Minstake cannot be zero");
        allowedTokens[tokenAddress] = minStake;
        emit TokenAllowed(tokenAddress, minStake);
    }

    // Function to whitelist an address as a tournament owner along with its associated tournament contract

    function addTournamentOwner(
        address _owner,
        address _tournamentContractAddress
    ) external onlyOwner {
        require(_owner != address(0), "Invalid owner address");
        require(
            _tournamentContractAddress != address(0),
            "Invalid tournament contract address"
        );
        tournamentOwners[_owner] = _tournamentContractAddress;
    }

    // Function to remove an address and its associated tournament contract from the whitelist
    function removeTournamentOwner(address _owner) external onlyOwner {
        require(
            tournamentOwners[_owner] != address(0),
            "Address is not a tournament owner"
        );
        delete tournamentOwners[_owner];
    }

    // Create a new game
    function createGame(
        uint256 stakeAmount,
        address tokenAddress,
        uint256 numberOfTurns,
        address player2
    ) external payable whenNotPaused nonReentrant {
        require(stakeAmount > 0, "Stake amount must be greater than zero");
        require(numberOfTurns > 0 && numberOfTurns % 2 == 1, "Invalid turns");
        require(player2 != address(0), "Player2 address is null");

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

        uint256 gameId = gameCounter.current(); // Get current gameId
        gameCounter.increment(); // Increment game counter
        updatePlayerGameStats(msg.sender, gameId);

        uint8[2][] memory initialChoices = new uint8[2][](numberOfTurns);
        for (uint256 i = 0; i < numberOfTurns; i++) {
            initialChoices[i] = [3, 3]; // 3 represents no choice made
        }

        games[gameId] = Game({
            player1: msg.sender,
            player2: player2,
            stakeAmount: stakeAmount,
            tokenAddress: tokenAddress,
            state: GameState.Waiting,
            numberOfTurns: numberOfTurns,
            player1Wins: 0,
            player2Wins: 0,
            lastActionTime: block.timestamp,
            winner: address(0),
            creationTime: block.timestamp,
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

    // Join the game
    function joinGame(
        uint256 gameId
    ) external payable whenNotPaused nonReentrant {
        Game storage game = games[gameId];
        require(game.player1 != address(0), "Game does not exist");
        require(game.state == GameState.Waiting, "Game not available to join");
        require(game.player2 == msg.sender, "You cannot join this game");

        if (game.tokenAddress == address(0)) {
            require(msg.value == game.stakeAmount, "Incorrect ETH amount sent");
        } else {
            IERC20(game.tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                game.stakeAmount
            );
        }

        updatePlayerGameStats(msg.sender, gameId);
        game.state = GameState.InProgress;
        game.lastActionTime = block.timestamp;

        emit GameJoined(gameId, msg.sender);
    }

    // Cancel game by players when it's in progress
    function cancelByAgreement(
        uint256 gameId
    ) external whenNotPaused onlyPlayers(gameId) nonReentrant {
        Game storage game = games[gameId];
        require(
            game.state == GameState.InProgress ||
                game.state == GameState.Dispute,
            "Game must be in progress or in dispute to cancel by agreement"
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
        uint8 player1Wins,
        uint8 player2Wins,
        uint8[2][] memory choices,
        bytes32 hash,
        bytes memory signature
    ) external whenNotPaused onlyOwner nonReentrant {
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

        bytes32 recomputedHash = keccak256(
            abi.encodePacked(gameId, player1Wins, player2Wins, winner)
        );
        require(recomputedHash == hash, "Hash mismatch");
        require(verifySignature(hash, signature), "Invalid signature");

        game.choices = choices;
        game.player1Wins = player1Wins;
        game.player2Wins = player2Wins;
        game.winner = winner;
        game.state = GameState.Completed;
        game.lastActionTime = block.timestamp;
        game.player1Dispute = false;
        game.player2Dispute = false;

        emit GameResultSubmitted(gameId, winner);
    }

    function approveWinner(
        uint256 gameId
    ) external whenNotPaused onlyOwner nonReentrant {
        Game storage game = games[gameId];
        require(game.state == GameState.Completed, "Game must be completed");
        require(
            block.timestamp > game.lastActionTime + disputePeriod,
            "Dispute window is still open"
        );

        address winner = game.winner;
        uint256 totalStake = game.stakeAmount.mul(2);
        _handleWinnerOrDraw(gameId, totalStake, winner);
        updatePlayerGameResultStats(gameId, winner);

        game.state = GameState.Settled;
        emit GameSettled(gameId, winner);
    }

    // Any one or both players submitting dispute within dispute period
    function raiseDispute(
        uint256 gameId
    ) external whenNotPaused onlyPlayers(gameId) nonReentrant {
        Game storage game = games[gameId];
        require(
            game.state == GameState.Completed,
            "Dispute can only be raised for completed games"
        );
        require(
            block.timestamp <= game.lastActionTime + disputePeriod,
            "Dispute period has expired"
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

    // Admin resolving dispute
    function resolveDispute(
        uint256 gameId,
        uint8 disputeId
    ) external onlyOwner whenNotPaused nonReentrant {
        Game storage game = games[gameId];
        require(game.state == GameState.Dispute, "No dispute to resolve");
        address winner = game.winner;
        uint256 totalStake = game.stakeAmount.mul(2);
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
        require(game.player1 == msg.sender, "Only game creator can cancel");
        require(game.state == GameState.Waiting, "Game has already started");
        require(
            block.timestamp > game.creationTime + gameExpirationTime,
            "Game has not expired yet"
        );

        transferFunds(
            game.player1,
            address(this),
            game.stakeAmount,
            game.tokenAddress
        );
        playerStats[game.player1].gamesCancelled++;
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
            amountAfterFee = amountAfterCut(totalStake, drawFee).div(2);
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

    function amountAfterCut(
        uint256 amount,
        uint256 cutInBasisPoints
    ) internal pure returns (uint256) {
        return amount.sub(amount.mul(cutInBasisPoints).div(FEE_DENOMINATOR));
    }

    function withdraw() external whenNotPaused nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw");

        pendingWithdrawals[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH withdrawal failed");

        emit Withdrawal(msg.sender, amount);
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

    // Helper functions for signature verification
    function verifySignature(
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(hash);
        address signer = recoverSigner(ethSignedMessageHash, signature);
        return signer == serverPublicKey;
    }

    function getEthSignedMessageHash(
        bytes32 _messageHash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    _messageHash
                )
            );
    }

    function recoverSigner(
        bytes32 _ethSignedMessageHash,
        bytes memory _signature
    ) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(
        bytes memory sig
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    // Prevent direct ETH transfers
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
            if (sender == address(this)) {
                (bool success, ) = receiver.call{value: amount}("");
                require(success, "ETH transfer failed");
            } else {
                pendingWithdrawals[receiver] = pendingWithdrawals[receiver].add(
                    amount
                );
            }
        } else {
            IERC20 token = IERC20(tokenAddress);
            if (sender == address(this)) {
                token.safeTransfer(receiver, amount);
            } else {
                token.safeTransferFrom(sender, receiver, amount);
            }
        }
    }

    // Create multiple tournament games between pairs of players
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
            "Input arrays must have the same length"
        );

        for (uint256 i = 0; i < player1s.length; i++) {
            require(numberOfTurnsList[i] > 0, "Invalid number of turns");

            uint256 gameId = gameCounter.current(); // Automatically assign the next gameId
            gameCounter.increment(); // Increment the game counter for the next game
            updatePlayerGameStats(player1s[i], gameId);
            updatePlayerGameStats(player2s[i], gameId);

            // Initialize choices with (3, 3) for each turn (no choice made)
            uint8[2][] memory initialChoices = new uint8[2][](
                numberOfTurnsList[i]
            );
            for (uint256 j = 0; j < numberOfTurnsList[i]; j++) {
                initialChoices[j] = [3, 3]; // 3 represents no choice made
            }

            // Create the game with no stake and no token address for tournament games
            games[gameId] = Game({
                player1: player1s[i],
                player2: player2s[i],
                stakeAmount: 0, // No stake for tournament games
                tokenAddress: address(0), // No token for tournament games
                state: GameState.InProgress,
                numberOfTurns: numberOfTurnsList[i],
                player1Wins: 0,
                player2Wins: 0,
                lastActionTime: block.timestamp,
                winner: address(0),
                creationTime: block.timestamp,
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

    // Admin function to approve and submit the result of a tournament game
    function SubmitAndApproveTournamentGame(
        uint256 gameId,
        address winner,
        uint8 player1Wins,
        uint8 player2Wins,
        uint8[2][] memory choices
    ) external onlyOwner whenNotPaused nonReentrant {
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

        // Update game choices and winner
        game.choices = choices;
        game.player1Wins = player1Wins;
        game.player2Wins = player2Wins;
        game.winner = winner;
        game.state = GameState.Settled; // Mark game as completed
        game.lastActionTime = block.timestamp;
        updatePlayerGameResultStats(gameId, winner);

        // Emit event for tournament game result
        emit TournamentGameResultSubmitted(gameId, winner);
    }
}
