// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockDEX {
    using SafeERC20 for IERC20;

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address to)
        external
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "MockDEX: zero amountIn");
        require(minAmountOut > 0, "MockDEX: zero minAmountOut");

        // Pull the tradeable input from the caller.
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // For the MVP, produce exactly the requested minimum output.
        amountOut = minAmountOut;

        // Transfer output to the recipient. The DEX must hold a balance of tokenOut.
        IERC20(tokenOut).safeTransfer(to, amountOut);

        return amountOut;
    }
}
