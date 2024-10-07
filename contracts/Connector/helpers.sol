// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Basic} from "./common/basic.sol";
import {IRockPaperScissorsGame} from "./interface.sol";

abstract contract Helpers is Basic {
    IRockPaperScissorsGame internal constant rockPaperScissorsGame =
        IRockPaperScissorsGame(0xA279C7Ba1740d442FF963280CC8e471A0679366e); // Replace with actual deployed game address
}
