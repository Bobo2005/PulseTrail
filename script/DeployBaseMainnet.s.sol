// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { PulseTrailCallback } from "../contracts/PulseTrailCallback.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";
import { MockUniswapV2Pair } from "../test/mocks/MockUniswapV2Pair.sol";
import { MockUniswapV2Router } from "../test/mocks/MockUniswapV2Router.sol";

/**
 * @title DeployBaseMainnet
 * @notice Foundry deployment script for **Base Mainnet (`8453`)**.
 *         Deploys and funds `PulseTrailCallback` wired to the official Base Callback Proxy
 *         (`0x0D3E76De6bC44309083cAAFdB49A088B8a250947`), and optionally deploys a deterministic
 *         demo ERC-20 pair if `DEPLOY_DEMO_PAIR=true` for live full-loop latency verification.
 *
 * Usage:
 *   forge script script/DeployBaseMainnet.s.sol:DeployBaseMainnet --rpc-url base_mainnet --broadcast
 */
contract DeployBaseMainnet is Script {
    address public constant DEFAULT_BASE_CALLBACK_PROXY =
        0x0D3E76De6bC44309083cAAFdB49A088B8a250947;
    address public constant DEFAULT_BASE_UNISWAP_V2_ROUTER =
        0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address callbackProxy = vm.envOr("BASE_CALLBACK_PROXY", DEFAULT_BASE_CALLBACK_PROXY);
        address uniswapRouterAddr = vm.envOr(
            "BASE_UNISWAP_V2_ROUTER",
            DEFAULT_BASE_UNISWAP_V2_ROUTER
        );
        bool deployDemoPair = vm.envOr("DEPLOY_DEMO_PAIR", true);
        uint256 initialFunding = vm.envOr("CALLBACK_INITIAL_FUNDING", uint256(0.0005 ether));

        vm.startBroadcast(deployerPrivateKey);

        address pairAddr = vm.envOr("UNISWAP_PAIR_ADDR", address(0));
        address tokenInAddr = address(0);
        address tokenOutAddr = address(0);

        if (deployDemoPair) {
            MockERC20 demoMeme = new MockERC20("PulseTrail Demo Token", "PTRAIL", 18);
            MockERC20 demoUsdc = new MockERC20("PulseTrail Demo USDC", "dUSDC", 18);

            MockUniswapV2Pair demoPair = new MockUniswapV2Pair(
                address(demoMeme),
                address(demoUsdc),
                1_000_000 ether,
                1_000_000 ether
            );
            MockUniswapV2Router demoRouter = new MockUniswapV2Router(address(demoPair));

            demoMeme.mint(deployer, 500_000 ether);
            demoUsdc.mint(address(demoRouter), 5_000_000 ether);

            tokenInAddr = address(demoMeme);
            tokenOutAddr = address(demoUsdc);
            pairAddr = address(demoPair);
            uniswapRouterAddr = address(demoRouter);
        }

        PulseTrailCallback callback = new PulseTrailCallback{ value: initialFunding }(
            callbackProxy,
            uniswapRouterAddr
        );

        callback.coverDebt();

        vm.stopBroadcast();

        console2.log("=== Base Mainnet (8453) Deployment Complete ===");
        console2.log("Deployer / RVM ID:      ", deployer);
        console2.log("Base Callback Proxy:    ", callbackProxy);
        console2.log("Uniswap V2 Router:      ", uniswapRouterAddr);
        console2.log("PulseTrailCallback:     ", address(callback));
        if (pairAddr != address(0)) {
            console2.log("Monitored Pair Address: ", pairAddr);
            console2.log("TokenIn (PTRAIL):       ", tokenInAddr);
            console2.log("TokenOut (dUSDC):       ", tokenOutAddr);
        }

        string memory json = string(
            abi.encodePacked(
                "{\n",
                '  "network": "base-mainnet",\n',
                '  "chainId": 8453,\n',
                '  "rpcUrl": "https://mainnet.base.org",\n',
                '  "explorer": "https://basescan.org",\n',
                '  "deployer": "', vm.toString(deployer), '",\n',
                '  "callbackProxy": "', vm.toString(callbackProxy), '",\n',
                '  "uniswapRouter": "', vm.toString(uniswapRouterAddr), '",\n',
                '  "pulseTrailCallback": "', vm.toString(address(callback)), '",\n',
                '  "monitoredPair": "', vm.toString(pairAddr), '",\n',
                '  "tokenIn": "', vm.toString(tokenInAddr), '",\n',
                '  "tokenOut": "', vm.toString(tokenOutAddr), '"\n',
                "}"
            )
        );

        vm.writeFile("./deployments/base-mainnet.json", json);
    }
}

