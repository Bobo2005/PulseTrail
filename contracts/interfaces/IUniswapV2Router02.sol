// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IUniswapV2Router02
 * @notice Minimal interface for the Uniswap V2 Router02 on Base Mainnet (`0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24`).
 *         Uses `swapExactTokensForTokensSupportingFeeOnTransferTokens` so fee-on-transfer memecoins
 *         are handled safely without reverting on router balance checks.
 */
interface IUniswapV2Router02 {
    /// @notice Returns the canonical factory address associated with the router.
    function factory() external view returns (address);

    /// @notice Returns the canonical wrapped native token (WETH) address.
    function WETH() external view returns (address);

    /**
     * @notice Given an input asset amount and an array of token addresses, calculates all subsequent
     *         maximum output token amounts by calling `getReserves` for each pair of token addresses in the path.
     * @param amountIn Input token amount.
     * @param path Array of token addresses representing the swap route (`[tokenIn, tokenOut]`).
     * @return amounts Array of output amounts along the path.
     */
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible,
     *         supporting tokens that take a fee on transfer.
     * @param amountIn The amount of input tokens to send.
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
     * @param path An array of token addresses (`[tokenIn, tokenOut]`).
     * @param to Recipient of the output tokens.
     * @param deadline Unix timestamp after which the transaction will revert.
     */
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}
