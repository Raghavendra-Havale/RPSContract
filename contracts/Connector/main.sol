// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccountInterface, TokenInterface} from "./common/interfaces.sol";
import {Helpers} from "./helpers.sol";
import {Events} from "./events.sol";

abstract contract Resolver is Events, Helpers {
    function createGame(
        uint256 stakeAmount,
        address tokenAddress,
        uint256 numberOfTurns
    )
        external
        payable
        returns (string memory _eventName, bytes memory _eventParam)
    {
        if (tokenAddress != address(0)) {
            require(
                rockPaperScissorsGame.getAllowedTokens(tokenAddress) != 0,
                "Token not allowed"
            );
            TokenInterface tokenContract = TokenInterface(tokenAddress);
            approve(tokenContract, address(rockPaperScissorsGame), stakeAmount);
        }
        rockPaperScissorsGame.createGame{value: msg.value}(
            stakeAmount,
            tokenAddress,
            numberOfTurns
        );

        _eventName = "LogCreateGame(uint256,address,address,uint256)";
        _eventParam = abi.encode(
            stakeAmount,
            tokenAddress,
            numberOfTurns,
            msg.sender
        );
    }

    function joinGame(
        uint256 gameId
    )
        external
        payable
        returns (string memory _eventName, bytes memory _eventParam)
    {
        (
            ,
            ,
            uint256 stakeAmount,
            address tokenAddress,
            ,
            ,
            ,

        ) = rockPaperScissorsGame.getGameDetails(gameId);

        if (tokenAddress != address(0)) {
            TokenInterface tokenContract = TokenInterface(tokenAddress);
            approve(tokenContract, address(rockPaperScissorsGame), stakeAmount);
        }
        rockPaperScissorsGame.joinGame{value: msg.value}(gameId);

        _eventName = "LogJoinGame(uint256,address)";
        _eventParam = abi.encode(gameId, msg.sender);
    }

    function cancelByAgreement(
        uint256 gameId
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        rockPaperScissorsGame.cancelByAgreement(gameId);

        _eventName = "LogCancelByAgreement(uint256)";
        _eventParam = abi.encode(gameId);
    }

    function cancelUnstartedGame(
        uint256 gameId
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        rockPaperScissorsGame.cancelUnstartedGame(gameId);

        _eventName = "LogcancelUnstartedGame(uint256)";
        _eventParam = abi.encode(gameId);
    }

    function raiseDispute(
        uint256 gameId
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        rockPaperScissorsGame.raiseDispute(gameId);

        _eventName = "LogRaiseDispute(uint256,address)";
        _eventParam = abi.encode(gameId, msg.sender);
    }
}

contract RPSConnector is Resolver {
    string public constant name = "RPSConnector-v1";
}
