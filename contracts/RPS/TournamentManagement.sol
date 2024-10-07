// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GameManagement.sol";

abstract contract TournamentManagement is GameManagement {
    mapping(address => address) public tournamentOwners;

    event TournamentGameCreated(
        uint256 indexed gameId,
        address indexed player1,
        address indexed player2,
        uint256 numberOfTurns,
        address tournamentContractAddress
    );
    event TournamentGameResultSubmitted(
        uint256 indexed gameId,
        address indexed winner
    );

    modifier onlyTournamentOwner(address tournamentContractAddress) {
        require(
            tournamentOwners[msg.sender] == tournamentContractAddress,
            "Caller is not the owner of the tournament contract"
        );
        _;
    }

    function addTournamentOwner(
        address _owner,
        address _tournamentContractAddress
    ) external {
        require(_owner != address(0), "Invalid owner address");
        require(
            _tournamentContractAddress != address(0),
            "Invalid tournament contract address"
        );
        tournamentOwners[_owner] = _tournamentContractAddress;
    }

    function removeTournamentOwner(address _owner) external {
        require(
            tournamentOwners[_owner] != address(0),
            "Address is not a tournament owner"
        );
        delete tournamentOwners[_owner];
    }

    function createTournamentGames(
        address[] calldata player1s,
        address[] calldata player2s,
        uint256[] calldata numberOfTurnsList,
        address tournamentContractAddress
    ) external onlyTournamentOwner(tournamentContractAddress) {
        require(
            player1s.length == player2s.length &&
                player1s.length == numberOfTurnsList.length,
            "Input arrays must match length"
        );

        for (uint256 i = 0; i < player1s.length; i++) {
            uint256 gameId = gameCounter; // Game counter inherited from GameManagement
            gameCounter++;

            // Add tournament logic for game creation here
            emit TournamentGameCreated(
                gameId,
                player1s[i],
                player2s[i],
                numberOfTurnsList[i],
                tournamentContractAddress
            );
        }
    }

    function submitTournamentGameResult(
        uint256 gameId,
        address winner
    ) external {
        // Add logic for submitting tournament game results
        emit TournamentGameResultSubmitted(gameId, winner);
    }
}
