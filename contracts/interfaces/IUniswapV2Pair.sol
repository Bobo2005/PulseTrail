// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IUniswapV2Pair
 * @notice Minimal Uniswap V2 / Aerodrome volatile pair interface for spot reserve inspection and `Sync` event decoding.
 */
interface IUniswapV2Pair {
    /**
     * @notice Emitted each time a pair's reserves are updated via mint, burn, or swap.
     *         Topic0: `0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1`
     * @param reserve0 Updated reserve of `token0`.
     * @param reserve1 Updated reserve of `token1`.
     */
    event Sync(uint112 reserve0, uint112 reserve1);

    /// @notice Returns the address of the pair's lower-sorted token (`token0`).
    function token0() external view returns (address);

    /// @notice Returns the address of the pair's higher-sorted token (`token1`).
    function token1() external view returns (address);

    /**
     * @notice Returns the current reserves of the pair and the last block timestamp of an update.
     * @return reserve0 Reserve of `token0`.
     * @return reserve1 Reserve of `token1`.
     * @return blockTimestampLast Timestamp of the last block in which reserves were updated.
     */
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}
