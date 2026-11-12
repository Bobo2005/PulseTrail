// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { PulseTrailReactive } from "../contracts/PulseTrailReactive.sol";

/**
 * @title DeployReactiveMainnet
 * @notice Foundry deployment script for **Reactive Mainnet (`1597`)**.
 *         Deploys and funds `PulseTrailReactive`, automatically subscribing to
 *         `PositionRegistered`, `PositionCancelled`, and `Sync` logs on Base Mainnet (`8453`).
 *
 * Usage:
 *   forge script script/DeployReactiveMainnet.s.sol:DeployReactiveMainnet --rpc-url reactive_mainnet --broadcast
 */
contract DeployReactiveMainnet is Script {
    uint256 public constant DEFAULT_ORIGIN_CHAIN_ID = 8453;
    address public constant REACTIVE_SERVICE_ADDR = 0x0000000000000000000000000000000000fffFfF;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 originChainId = vm.envOr("BASE_MAINNET_CHAIN_ID", DEFAULT_ORIGIN_CHAIN_ID);
        address callbackAddr = vm.envAddress("PULSE_TRAIL_CALLBACK_ADDR");
        address pairAddr = vm.envOr("UNISWAP_PAIR_ADDR", address(0));
        uint256 reactiveFunding = vm.envOr("REACTIVE_INITIAL_FUNDING", uint256(1 ether));

        vm.startBroadcast(deployerPrivateKey);

        PulseTrailReactive reactive = new PulseTrailReactive{ value: reactiveFunding }(
            originChainId,
            callbackAddr,
            pairAddr
        );

        reactive.coverDebt();

        vm.stopBroadcast();

        console2.log("=== Reactive Mainnet (1597) Deployment Complete ===");
        console2.log("Deployer / RVM ID:      ", deployer);
        console2.log("System Service Addr:    ", REACTIVE_SERVICE_ADDR);
        console2.log("Origin Chain ID:        ", originChainId);
        console2.log("Target Callback Addr:   ", callbackAddr);
        console2.log("Subscribed Pair Addr:   ", pairAddr);
        console2.log("PulseTrailReactive:     ", address(reactive));

        string memory json = string(
            abi.encodePacked(
                "{\n",
                '  "network": "reactive-mainnet",\n',
                '  "chainId": 1597,\n',
                '  "rpcUrl": "https://mainnet-rpc.rnk.dev/",\n',
                '  "explorer": "https://reactscan.net",\n',
                '  "deployer": "', vm.toString(deployer), '",\n',
                '  "serviceAddress": "', vm.toString(REACTIVE_SERVICE_ADDR), '",\n',
                '  "originChainId": ', vm.toString(originChainId), ",\n",
                '  "pulseTrailCallback": "', vm.toString(callbackAddr), '",\n',
                '  "subscribedPair": "', vm.toString(pairAddr), '",\n',
                '  "pulseTrailReactive": "', vm.toString(address(reactive)), '"\n',
                "}"
            )
        );

        vm.writeFile("./deployments/reactive-mainnet.json", json);
    }
}

