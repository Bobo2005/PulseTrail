// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IUniswapV2Router02 } from "../../contracts/interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Pair } from "../../contracts/interfaces/IUniswapV2Pair.sol";
import { IERC20 } from "../../contracts/interfaces/IERC20.sol";
import { MockERC20 } from "./MockERC20.sol";

/**
 * @title MockUniswapV2Router
 * @notice Simulated Uniswap V2 Router02 that calculates swap outputs from the registered
 *         `MockUniswapV2Pair`'s current reserve ratio, enforces `amountOut >= amountOutMin`,
 *         and supports fee-on-transfer and honeypot token testing.
 */
contract MockUniswapV2Router is IUniswapV2Router02 {
    address public override factory;
    address public override WETH;
    address public defaultPair;

    /// @notice Maps `tokenA => tokenB => pair`.
    mapping(address => mapping(address => address)) public pairs;

    constructor(address _defaultPair) {
        defaultPair = _defaultPair;
        factory = address(this);
        WETH = address(0x4200000000000000000000000000000000000006);
        if (_defaultPair != address(0)) {
            address t0 = IUniswapV2Pair(_defaultPair).token0();
            address t1 = IUniswapV2Pair(_defaultPair).token1();
            pairs[t0][t1] = _defaultPair;
            pairs[t1][t0] = _defaultPair;
        }
    }

    function registerPair(address pair) external {
        require(pair != address(0), "Router: zero pair");
        defaultPair = pair;
        address t0 = IUniswapV2Pair(pair).token0();
        address t1 = IUniswapV2Pair(pair).token1();
        pairs[t0][t1] = pair;
        pairs[t1][t0] = pair;
    }

    function getPair(address tokenA, address tokenB) public view returns (address pair) {
        pair = pairs[tokenA][tokenB];
        if (pair == address(0)) {
            pair = defaultPair;
        }
        require(pair != address(0), "Router: pair not registered");
    }

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) public view override returns (uint256[] memory amounts) {
        require(path.length >= 2, "Router: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < path.length - 1; ++i) {
            address pair = getPair(path[i], path[i + 1]);
            address token0 = IUniswapV2Pair(pair).token0();
            (uint112 r0, uint112 r1, ) = IUniswapV2Pair(pair).getReserves();

            uint256 reserveIn = (path[i] == token0) ? uint256(r0) : uint256(r1);
            uint256 reserveOut = (path[i] == token0) ? uint256(r1) : uint256(r0);
            require(reserveIn > 0 && reserveOut > 0, "Router: INSUFFICIENT_LIQUIDITY");

            amounts[i + 1] = (amounts[i] * reserveOut) / reserveIn;
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override {
        require(block.timestamp <= deadline, "Router: EXPIRED");
        require(path.length == 2, "Router: INVALID_PATH");

        address tokenIn = path[0];
        address tokenOut = path[1];
        address pair = getPair(tokenIn, tokenOut);

        // Measure actual received input tokens (handles fee-on-transfer and triggers honeypot reverts)
        uint256 balBefore = IERC20(tokenIn).balanceOf(address(this));
        bool ok = IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        require(ok, "Router: TRANSFER_FROM_FAILED");
        uint256 actualIn = IERC20(tokenIn).balanceOf(address(this)) - balBefore;

        address token0 = IUniswapV2Pair(pair).token0();
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(pair).getReserves();
        uint256 reserveIn = (tokenIn == token0) ? uint256(r0) : uint256(r1);
        uint256 reserveOut = (tokenIn == token0) ? uint256(r1) : uint256(r0);
        require(reserveIn > 0 && reserveOut > 0, "Router: INSUFFICIENT_LIQUIDITY");

        uint256 amountOut = (actualIn * reserveOut) / reserveIn;
        require(amountOut >= amountOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");

        // Deliver output tokens to recipient (transfer from router balance if funded, else mint)
        uint256 routerOutBal = IERC20(tokenOut).balanceOf(address(this));
        if (routerOutBal >= amountOut) {
            require(IERC20(tokenOut).transfer(to, amountOut), "Router: TRANSFER_OUT_FAILED");
        } else {
            MockERC20(tokenOut).mint(to, amountOut);
        }
    }
}

