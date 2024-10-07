// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Events {
    event LogCreateGame(
        uint256 stakeAmount,
        address tokenAddress,
        uint256 numberOfTurns,
        address creator
    );
    event LogJoinGame(uint256 gameId, address player);
    event LogCancelByAgreement(uint256 gameId);
    event LogCancelUnstartedGame(uint256 gameId);
    event LogRaiseDispute(uint256 gameId, address player);
}
