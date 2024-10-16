// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PublicAuction.sol";

contract DeployPublicAuction is Script {
    function run() external {
        vm.startBroadcast();

        // 部署PublicAuction合约
        PublicAuction auction = new PublicAuction(1 days); // 设置拍卖持续时间为1天

        console.log("PublicAuction deployed at:", address(auction));

        vm.stopBroadcast();
    }
}
