// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function warp(uint256 newTimestamp) external;
    function roll(uint256 newHeight) external;
    function deal(address who, uint256 newBalance) external;
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function expectRevert() external;
    function expectRevert(bytes calldata revertData) external;
    function expectRevert(bytes4 revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function expectEmit(
        bool checkTopic1,
        bool checkTopic2,
        bool checkTopic3,
        bool checkData,
        address emitter
    ) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory logs);
    function assume(bool condition) external pure;
    function addr(uint256 privateKey) external pure returns (address keyAddr);
    function envUint(string calldata name) external view returns (uint256 value);
    function envAddress(string calldata name) external view returns (address value);
    function envBool(string calldata name) external view returns (bool value);
    function envString(string calldata name) external view returns (string memory value);
    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256 value);
    function envOr(string calldata name, address defaultValue) external view returns (address value);
    function envOr(string calldata name, bool defaultValue) external view returns (bool value);
    function envOr(string calldata name, string calldata defaultValue) external view returns (string memory value);
    function startBroadcast() external;
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
    function writeFile(string calldata path, string calldata data) external;
    function writeJson(string calldata json, string calldata path) external;
    function toString(address value) external pure returns (string memory stringifiedValue);
    function toString(uint256 value) external pure returns (string memory stringifiedValue);
}

