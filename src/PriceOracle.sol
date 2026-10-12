// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SimpleAMM} from "./SimpleAMM.sol";

/// @title WGLD price feed for the lending pool.
contract PriceOracle {
    address public owner;
    SimpleAMM public amm;

    constructor(SimpleAMM market) {
        owner = msg.sender;
        amm = market;
    }

    function setAmm(SimpleAMM market) external {
        require(msg.sender == owner, "only owner");
        amm = market;
    }

    /// @notice Native USDC per whole WGLD (18 decimals), read from the AMM.
    function price() external view returns (uint256) {
        return amm.spotPrice();
    }
}
