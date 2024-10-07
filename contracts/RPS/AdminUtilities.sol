// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract AdminUtilities is Ownable {
    uint256 public protocolFee = 20; // 0.2% in basis points
    uint256 public drawFee = 5; // 0.05% in basis points
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public disputePeriod = 1 hours;
    address public serverPublicKey;

    mapping(address => uint256) public allowedTokens; // Mapping for allowed tokens and their minimum stake

    event ProtocolFeeUpdated(uint256 newFee);
    event DrawFeeUpdated(uint256 newFee);
    event DisputePeriodUpdated(uint256 newPeriod);

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

    function updateDisputePeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod <= 1 hours, "Dispute period too long");
        disputePeriod = newPeriod;
        emit DisputePeriodUpdated(newPeriod);
    }

    function allowToken(
        address tokenAddress,
        uint256 minStake
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(minStake > 0, "Minstake cannot be zero");
        allowedTokens[tokenAddress] = minStake;
    }
}
