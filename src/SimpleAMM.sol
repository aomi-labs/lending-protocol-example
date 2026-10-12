// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CollateralToken} from "./CollateralToken.sol";

/// @title Native-USDC / WGLD constant-product pool with a 0.3% fee.
contract SimpleAMM {
    CollateralToken public immutable token;
    uint256 public reserveNative;
    uint256 public reserveToken;

    event Swap(address indexed trader, bool buy, uint256 amountIn, uint256 amountOut);

    constructor(CollateralToken collateral) {
        token = collateral;
    }

    /// @notice Initial liquidity, provided once at deployment.
    function seed(uint256 tokenAmount) external payable {
        require(reserveNative == 0 && reserveToken == 0, "seeded");
        require(token.transferFrom(msg.sender, address(this), tokenAmount), "transfer");
        reserveNative = msg.value;
        reserveToken = tokenAmount;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    /// @notice Buy WGLD with native USDC.
    function buy(uint256 minOut) external payable returns (uint256 out) {
        out = getAmountOut(msg.value, reserveNative, reserveToken);
        require(out > 0 && out >= minOut, "slippage");
        reserveNative += msg.value;
        reserveToken -= out;
        require(token.transfer(msg.sender, out), "transfer");
        emit Swap(msg.sender, true, msg.value, out);
    }

    /// @notice Sell WGLD for native USDC (requires an approval).
    function sell(uint256 amountIn, uint256 minOut) external returns (uint256 out) {
        require(token.transferFrom(msg.sender, address(this), amountIn), "transfer");
        out = getAmountOut(amountIn, reserveToken, reserveNative);
        require(out > 0 && out >= minOut, "slippage");
        reserveToken += amountIn;
        reserveNative -= out;
        (bool ok,) = msg.sender.call{value: out}("");
        require(ok, "native transfer");
        emit Swap(msg.sender, false, amountIn, out);
    }

    /// @notice Native USDC per whole WGLD (18 decimals).
    function spotPrice() external view returns (uint256) {
        return (reserveNative * 1e18) / reserveToken;
    }
}
