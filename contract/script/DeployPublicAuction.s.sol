// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PublicAuction.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployPublicAuction is Script {
    function run() external {
        vm.startBroadcast();

        // 部署实现合约
        PublicAuction implementation = new PublicAuction();

        // 编码初始化调用
        bytes memory data = abi.encodeWithSelector(
            PublicAuction.initialize.selector,
            1 days, // 拍卖持续时间
            address(0x24f3b416412388FE3108D614036dA06fB9C6f348) // 受益人地址
        );

        // 部署代理合约
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        // 获取代理的PublicAuction接口
        PublicAuction auction = PublicAuction(address(proxy));

        console.log("PublicAuction deployed at:", address(auction));

        vm.stopBroadcast();
    }
}
