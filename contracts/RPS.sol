// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract RockPaperScissorsGame is Pausable {
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
        uint256 player1Wins;
        uint256 player2Wins;
        uint256 lastActionTime;
        address winner;
        uint256 creationTime;
        bool player1Dispute;
        bool player2Dispute;
    }

    mapping(bytes32 => Game) public games; // Mapping of game session IDs to games
    mapping(address => uint256) public pendingWithdrawals; // For handling withdrawals

    address public owner;
    address public serverPublicKey; // Public key of the off-chain server

    uint256 public disputePeriod = 1 hours; // Configurable dispute period
    uint256 public gameExpirationTime = 24 hours; // Time after which unstarted games can be cancelled
    uint256 public maxTurns = 7; // Maximum number of turns, must be odd

    event GameCreated(
        bytes32 indexed gameId,
        address indexed player1,
        uint256 stakeAmount,
        address tokenAddress,
        uint256 numberOfTurns
    );
    event GameJoined(bytes32 indexed gameId, address indexed player2);
    event GameResultSubmitted(bytes32 indexed gameId, address indexed winner);
    event DisputeRaised(bytes32 indexed gameId, address indexed player);
    event GameCancelled(bytes32 indexed gameId);
    event GameSettled(bytes32 indexed gameId, address indexed winner);
    event Withdrawal(address indexed player, uint256 amount);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event ServerPublicKeyUpdated(
        address indexed oldKey,
        address indexed newKey
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyPlayers(bytes32 gameId) {
        require(
            msg.sender == games[gameId].player1 ||
                msg.sender == games[gameId].player2,
            "Only players involved in the game can call this"
        );
        _;
    }

    constructor(address _serverPublicKey) {
        owner = msg.sender;
        serverPublicKey = _serverPublicKey;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setServerPublicKey(address newKey) external onlyOwner {
        require(newKey != address(0), "New key is zero address");
        emit ServerPublicKeyUpdated(serverPublicKey, newKey);
        serverPublicKey = newKey;
    }

    function enterGame(
        bytes32 gameId,
        uint256 stakeAmount,
        address tokenAddress,
        uint256 numberOfTurns,
        address player2
    ) external payable whenNotPaused {
        require(games[gameId].player1 == address(0), "Game already exists");
        require(stakeAmount > 0, "Stake amount must be greater than zero");
        require(
            numberOfTurns > 0 && numberOfTurns % 2 == 1,
            "Number of turns must be an odd number"
        );
        require(player2 != address(0), "Player2 address is null");

        if (tokenAddress == address(0)) {
            require(msg.value == stakeAmount, "Incorrect ETH amount sent");
        } else {
            IERC20 token = IERC20(tokenAddress);
            token.safeTransferFrom(msg.sender, address(this), stakeAmount);
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
            player2Dispute: false
        });

        emit GameCreated(
            gameId,
            msg.sender,
            stakeAmount,
            tokenAddress,
            numberOfTurns
        );
    }

    function joinGame(bytes32 gameId) external payable whenNotPaused {
        Game storage game = games[gameId];
        require(game.player1 != address(0), "Game does not exist");
        require(game.state == GameState.Waiting, "Game not available to join");
        require(game.player2 == msg.sender, "You cannot join this game");

        if (game.tokenAddress == address(0)) {
            require(msg.value == game.stakeAmount, "Incorrect ETH amount sent");
        } else {
            IERC20 token = IERC20(game.tokenAddress);
            token.safeTransferFrom(msg.sender, address(this), game.stakeAmount);
        }
        game.state = GameState.InProgress;
        game.lastActionTime = block.timestamp;

        emit GameJoined(gameId, msg.sender);
    }

    //Cancel game by players when its in progress
    function cancelByAgreement(
        bytes32 gameId
    ) external whenNotPaused onlyPlayers(gameId) {
        Game storage game = games[gameId];
        require(
            game.state == GameState.InProgress ||
                game.state == GameState.Dispute,
            "Game must be in progress or in dispute to cancel by agreement"
        );

        if (msg.sender == game.player1) {
            require(
                !game.player1Dispute,
                "Player1 has already agreed to cancel"
            );
            game.player1Dispute = true;
        } else if (msg.sender == game.player2) {
            require(
                !game.player2Dispute,
                "Player2 has already agreed to cancel"
            );
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
            game.state = GameState.Cancelled;

            emit GameCancelled(gameId);
        }
    }

    function submitGameResult(
        bytes32 gameId,
        address winner,
        uint8 player1Wins,
        bytes32 hash,
        bytes memory signature,
        uint8 player2Wins
    ) external whenNotPaused onlyOwner {
        Game storage game = games[gameId];
        require(game.state == GameState.InProgress, "Game is not in progress");
        require(
            winner == game.player1 ||
                winner == game.player2 ||
                winner == address(0),
            "Invalid winner address"
        );

        // Recompute the hash based on the provided data
        bytes32 recomputedHash = keccak256(
            abi.encodePacked(gameId, player1Wins, player2Wins, winner)
        );

        // Verify that the recomputed hash matches the provided hash
        require(recomputedHash == hash, "Hash mismatch");

        // Verify the signature using the server's public key
        require(verifySignature(hash, signature), "Invalid signature");

        game.player1Wins = player1Wins;
        game.player2Wins = player2Wins;
        game.winner = winner;
        game.state = GameState.Completed;
        game.lastActionTime = block.timestamp;
        game.player1Dispute = false;
        game.player2Dispute = false;

        emit GameResultSubmitted(gameId, winner);
    }

    //Approving winner incase of no dispute
    function approveWinner(bytes32 gameId) external whenNotPaused onlyOwner {
        Game storage game = games[gameId];
        require(game.state == GameState.Completed, "Game must be completed");
        require(
            block.timestamp > game.lastActionTime + disputePeriod,
            "Dispute window is still open"
        );
        address winner = game.winner;
        uint256 totalStake = game.stakeAmount * 2;
        if (winner == address(0)) {
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
        } else {
            transferFunds(winner, address(this), totalStake, game.tokenAddress);
        }

        game.state = GameState.Settled; // Set game state to Settled after funds are distributed

        emit GameSettled(gameId, winner);
    }

    //Any one or both players submitting dispute within dispute period
    function raiseDispute(
        bytes32 gameId
    ) external whenNotPaused onlyPlayers(gameId) {
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

    //Admin resolving dispute
    //0=Match drawn
    //1=original winner is the winner
    //2=other player is the winner
    function resolveDispute(
        bytes32 gameId,
        uint8 disputeId
    ) external onlyOwner whenNotPaused {
        Game storage game = games[gameId];
        require(game.state == GameState.Dispute, "No dispute to resolve");
        address winner = game.winner;
        uint256 totalStake = game.stakeAmount * 2;
        address otherPlayer = (game.winner == game.player1)
            ? game.player2
            : game.player1;

        if (disputeId == 0) {
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
            emit GameSettled(gameId, address(0));
        } else if (disputeId == 1) {
            transferFunds(winner, address(this), totalStake, game.tokenAddress);
            emit GameSettled(gameId, winner);
        } else if (disputeId == 2) {
            transferFunds(
                otherPlayer,
                address(this),
                totalStake,
                game.tokenAddress
            );
            emit GameSettled(gameId, otherPlayer);
        } else {
            revert("Invalid dispute resolution option");
        }

        game.state = GameState.Settled; // After dispute resolution, game is Settled
    }

    function cancelUnstartedGame(bytes32 gameId) external {
        Game storage game = games[gameId];
        require(game.player1 == msg.sender, "Only the game creator can cancel");
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
    }

    function withdraw() external whenNotPaused {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw");

        pendingWithdrawals[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH withdrawal failed");

        emit Withdrawal(msg.sender, amount);
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

        assembly ("memory-safe") {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    // Prevent direct ETH transfers
    receive() external payable {
        revert("Direct ETH transfers not allowed");
    }

    // Unified fund transfer function for ETH or ERC20
    function transferFunds(
        address receiver,
        address sender,
        uint256 amount,
        address tokenAddress
    ) internal {
        if (tokenAddress == address(0)) {
            // Transfer ETH
            if (sender == address(this)) {
                (bool success, ) = receiver.call{value: amount}("");
                require(success, "ETH transfer failed");
            } else {
                pendingWithdrawals[receiver] += amount;
            }
        } else {
            // Transfer ERC20
            IERC20 token = IERC20(tokenAddress);
            if (sender == address(this)) {
                token.safeTransfer(receiver, amount);
            } else {
                token.safeTransferFrom(sender, receiver, amount);
            }
        }
    }
}
