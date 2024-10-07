// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract PlayerManagement {
    struct PlayerStats {
        uint256 gamesPlayed;
        uint256 gamesWon;
        uint256 gamesLost;
        uint256 gamesDrawn;
        uint256 gamesCancelled;
        uint256[] gameIds;
    }

    mapping(address => PlayerStats) public playerStats;

    function updatePlayerStats(address player, uint256 gameId) internal {
        PlayerStats storage stats = playerStats[player];
        stats.gamesPlayed++;
        stats.gameIds.push(gameId);
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
}
