// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SushiFlush is ERC20 {
    constructor() ERC20("SushiFlush", "SFLUSH") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}
