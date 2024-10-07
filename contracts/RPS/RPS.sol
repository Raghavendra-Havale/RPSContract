// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GameManagement.sol";
import "./TournamentManagement.sol";
import "./AdminUtilities.sol";
import "./PlayerManagement.sol";

contract RockPaperScissors is TournamentManagement, PlayerManagement {
    constructor(address _serverPublicKey) Ownable(msg.sender) {
        serverPublicKey = _serverPublicKey;
        gameCounter = 1; // Initialize the game counter
    }

    // This contract will now have access to all functions and storage from the abstract contracts.
}
