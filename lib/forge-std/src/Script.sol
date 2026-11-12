// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Vm } from "./Vm.sol";
import { console2 } from "./Test.sol";

abstract contract Script {
    Vm public constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bool public IS_SCRIPT = true;
}

