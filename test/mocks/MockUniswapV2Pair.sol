// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IUniswapV2Pair } from "../../contracts/interfaces/IUniswapV2Pair.sol";

/**
 * @title MockUniswapV2Pair
 * @notice Simulated Uniswap V2 Pair that stores `(reserve0, reserve1)` and emits canonical
 *         `Sync(uint112 reserve0, uint112 reserve1)` events when `setReserves` is called.
 */
contract MockUniswapV2Pair is IUniswapV2Pair {
    address public immutable override token0;
    address public immutable override token1;

    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32 private _blockTimestampLast;

    constructor(
        address _token0,
        address _token1,
        uint112 initialReserve0,
        uint112 initialReserve1
    ) {
        require(_token0 != address(0) && _token1 != address(0), "Pair: zero address");
        token0 = _token0;
        token1 = _token1;
        _reserve0 = initialReserve0;
        _reserve1 = initialReserve1;
        _blockTimestampLast = uint32(block.timestamp);
    }

    function getReserves()
        external
        view
        override
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        )
    {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    /**
     * @notice Updates the pair's reserves and emits `Sync(r0, r1)`.
     */
    function setReserves(uint112 r0, uint112 r1) external {
        _reserve0 = r0;
        _reserve1 = r1;
        _blockTimestampLast = uint32(block.timestamp);
        emit Sync(r0, r1);
    }
}

