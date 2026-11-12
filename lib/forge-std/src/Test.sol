// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Vm } from "./Vm.sol";

library console2 {
    address constant CONSOLE_ADDRESS = 0x000000000000000000636F6e736F6c652e6c6f67;

    function _sendLogPayload(bytes memory payload) private view {
        address consoleAddress = CONSOLE_ADDRESS;
        assembly {
            pop(staticcall(gas(), consoleAddress, add(payload, 32), mload(payload), 0, 0))
        }
    }

    function log(string memory p0) internal view {
        _sendLogPayload(abi.encodeWithSignature("log(string)", p0));
    }

    function log(string memory p0, uint256 p1) internal view {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint256)", p0, p1));
    }

    function log(string memory p0, address p1) internal view {
        _sendLogPayload(abi.encodeWithSignature("log(string,address)", p0, p1));
    }

    function log(string memory p0, string memory p1) internal view {
        _sendLogPayload(abi.encodeWithSignature("log(string,string)", p0, p1));
    }
}

abstract contract Test {
    Vm public constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bool public IS_TEST = true;

    function fail(string memory err) internal pure {
        revert(err);
    }

    function assertTrue(bool condition) internal pure {
        require(condition, "Assertion failed: expected true");
    }

    function assertTrue(bool condition, string memory err) internal pure {
        require(condition, err);
    }

    function assertFalse(bool condition) internal pure {
        require(!condition, "Assertion failed: expected false");
    }

    function assertFalse(bool condition, string memory err) internal pure {
        require(!condition, err);
    }

    function assertEq(uint256 a, uint256 b) internal pure {
        require(a == b, "Assertion failed: uint256 not equal");
    }

    function assertEq(uint256 a, uint256 b, string memory err) internal pure {
        require(a == b, err);
    }

    function assertEq(address a, address b) internal pure {
        require(a == b, "Assertion failed: address not equal");
    }

    function assertEq(address a, address b, string memory err) internal pure {
        require(a == b, err);
    }

    function assertEq(bool a, bool b) internal pure {
        require(a == b, "Assertion failed: bool not equal");
    }

    function assertEq(bytes32 a, bytes32 b) internal pure {
        require(a == b, "Assertion failed: bytes32 not equal");
    }

    function assertGt(uint256 a, uint256 b) internal pure {
        require(a > b, "Assertion failed: expected a > b");
    }

    function assertGt(uint256 a, uint256 b, string memory err) internal pure {
        require(a > b, err);
    }

    function assertGe(uint256 a, uint256 b) internal pure {
        require(a >= b, "Assertion failed: expected a >= b");
    }

    function assertGe(uint256 a, uint256 b, string memory err) internal pure {
        require(a >= b, err);
    }

    function assertLt(uint256 a, uint256 b) internal pure {
        require(a < b, "Assertion failed: expected a < b");
    }

    function assertLt(uint256 a, uint256 b, string memory err) internal pure {
        require(a < b, err);
    }

    function assertLe(uint256 a, uint256 b) internal pure {
        require(a <= b, "Assertion failed: expected a <= b");
    }

    function assertLe(uint256 a, uint256 b, string memory err) internal pure {
        require(a <= b, err);
    }

    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256 result) {
        require(min <= max, "bound: min > max");
        if (x >= min && x <= max) return x;
        uint256 size = max - min + 1;
        if (size == 0) return x;
        return min + (x % size);
    }
}

