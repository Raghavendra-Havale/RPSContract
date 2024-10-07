// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRockPaperScissorsGame {
    enum GameState {
        Waiting,
        InProgress,
        Completed,
        Dispute,
        Cancelled,
        Settled
    }

    function createGame(
        uint256 stakeAmount,
        address tokenAddress,
        uint256 numberOfTurns
    ) external payable;

    function joinGame(uint256 gameId) external payable;

    function cancelByAgreement(uint256 gameId) external;
    function cancelUnstartedGame(uint256 gameId) external;
    function raiseDispute(uint256 gameId) external;
    function getAllowedTokens(
        address tokenAddress
    ) external view returns (uint256);
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
        );
}
