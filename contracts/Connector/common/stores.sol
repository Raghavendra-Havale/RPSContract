//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MemoryInterface, PeerToPlayMapping, ListInterface, PeerToPlayConnectors} from "./interfaces.sol";

abstract contract Stores {
    /**
     * @dev Return ethereum address
     */
    address internal constant ethAddr =
        0x0000000000000000000000000000000000000000;

    /**
     * @dev Return Wrapped ETH address
     */
    address internal constant wethAddr =
        0x015fB54ab5F94F4194C2c61F20c1FCf6066400a9;

    /**
     * @dev Return memory variable address
     */
    MemoryInterface internal constant PeerToPlayMemory =
        MemoryInterface(0x4Fbce56121B8b1aC49b8414F1E1615b79AF34079);

    /**
     * @dev Return PeerToPlayList address
     */
    ListInterface internal constant PeerToPlayList =
        ListInterface(0x6d5378F4cC2523a537CEBbd6578D8792a7709DCB);

    /**
     * @dev Return connectors registry address
     */
    PeerToPlayConnectors internal constant peerToPlayConnectors =
        PeerToPlayConnectors(0x3B5a0e8a98E78730fBa647fF6bBE62124D398535);

    /**
     * @dev Get Uint value from PeerToPlayMemory Contract.
     */
    function getUint(uint getId, uint val) internal returns (uint returnVal) {
        returnVal = getId == 0 ? val : PeerToPlayMemory.getUint(getId);
    }

    /**
     * @dev Set Uint value in PeerToPlayMemory Contract.
     */
    function setUint(uint setId, uint val) internal virtual {
        if (setId != 0) PeerToPlayMemory.setUint(setId, val);
    }
}
