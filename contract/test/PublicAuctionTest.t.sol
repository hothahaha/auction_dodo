// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PublicAuction.sol";

contract PublicAuctionTest is Test {
    PublicAuction public auction;
    address public beneficiary;
    uint256 public constant AUCTION_DURATION = 1 days;

    function setUp() public {
        beneficiary = makeAddr("beneficiary");
        auction = new PublicAuction(AUCTION_DURATION);
    }

    function testInitialState() public view {
        assertEq(auction.auctionEndTime(), block.timestamp + AUCTION_DURATION);
        assertEq(auction.highestBid(), 0);
        assertEq(auction.highestBidder(), address(0));
        assertFalse(auction.ended());
    }

    function testBidding() public {
        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);
        uint256 bidAmount = 1 ether;
        vm.deal(address(this), bidAmount);
        auction.bid{value: bidAmount}();

        assertEq(auction.highestBid(), bidAmount);
        assertEq(auction.highestBidder(), address(this));
    }

    function testMultipleBids() public {
        address bidder1 = makeAddr("bidder1");
        address bidder2 = makeAddr("bidder2");

        vm.deal(bidder1, 1 ether);
        vm.deal(bidder2, 2 ether);

        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);
        vm.prank(bidder1);
        auction.bid{value: 1 ether}();

        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);
        vm.prank(bidder2);
        auction.bid{value: 2 ether}();

        assertEq(auction.highestBid(), 2 ether);
        assertEq(auction.highestBidder(), bidder2);
        assertEq(auction.pendingReturns(bidder1), 1 ether);
    }

    function testWithdraw() public {
        address bidder1 = makeAddr("bidder1");
        address bidder2 = makeAddr("bidder2");

        vm.deal(bidder1, 1 ether);
        vm.deal(bidder2, 2 ether);

        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);

        vm.prank(bidder1);
        auction.bid{value: 1 ether}();

        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);

        vm.prank(bidder2);
        auction.bid{value: 2 ether}();

        vm.prank(bidder1);
        bool success = auction.withdraw();

        assertTrue(success);
        assertEq(bidder1.balance, 1 ether);
        assertEq(auction.pendingReturns(bidder1), 0);
    }

    function testFailedWithdraw() public {
        address bidder = makeAddr("bidder");
        vm.deal(bidder, 1 ether);

        vm.prank(bidder);
        auction.bid{value: 1 ether}();

        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);

        vm.prank(address(this));
        auction.bid{value: 2 ether}();

        // 创建一个恶意合约来模拟withdraw失败
        MaliciousContract malicious = new MaliciousContract();
        vm.prank(address(malicious));
        auction.bid{value: 3 ether}();

        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);

        vm.prank(address(this));
        auction.bid{value: 4 ether}();

        vm.prank(address(malicious));
        bool success = auction.withdraw();

        assertFalse(success);
        assertEq(auction.pendingReturns(address(malicious)), 3 ether);
    }

    function testAuctionEnd() public {
        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);
        uint256 bidAmount = 1 ether;
        vm.deal(address(this), bidAmount);
        auction.bid{value: bidAmount}();

        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        auction.auctionEnd();

        assertTrue(auction.ended());
        assertEq(auction.owner().balance, bidAmount);
    }

    function testBidAfterEnd() public {
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        vm.expectRevert(
            PublicAuction.PublicAuction__AuctionAlreadyEnded.selector
        );
        auction.bid{value: 1 ether}();
    }

    function testLowerBid() public {
        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);
        auction.bid{value: 2 ether}();
        vm.expectRevert(
            abi.encodeWithSelector(
                PublicAuction.PublicAuction__BidNotHighEnough.selector,
                2 ether
            )
        );
        auction.bid{value: 1 ether}();
    }

    function testBiddingCooldown() public {
        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);
        auction.bid{value: 1 ether}();
        vm.expectRevert(
            PublicAuction.PublicAuction__BiddingCooldownNotExpired.selector
        );
        auction.bid{value: 2 ether}();
    }

    function testEndAuctionTooEarly() public {
        vm.expectRevert(
            PublicAuction.PublicAuction__AuctionNotYetEnded.selector
        );
        auction.auctionEnd();
    }

    function testEndAuctionTwice() public {
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        auction.auctionEnd();
        vm.expectRevert(
            PublicAuction.PublicAuction__AuctionEndAlreadyCalled.selector
        );
        auction.auctionEnd();
    }

    function testTimeWeightedBid() public {
        vm.warp(
            block.timestamp +
                AUCTION_DURATION -
                auction.TIME_WEIGHT_PERIOD() +
                1
        );
        uint256 bidAmount = 1 ether;
        vm.deal(address(this), bidAmount);
        auction.bid{value: bidAmount}();

        assertEq(auction.highestBid(), bidAmount);
        assertEq(auction.highestBidder(), address(this));
    }

    function testAuctionExtension() public {
        vm.warp(
            block.timestamp +
                AUCTION_DURATION -
                auction.AUCTION_EXTENSION_PERIOD() +
                1
        );
        uint256 bidAmount = 1 ether;
        vm.deal(address(this), bidAmount);
        auction.bid{value: bidAmount}();

        assertEq(
            auction.auctionEndTime(),
            block.timestamp + auction.AUCTION_EXTENSION_PERIOD()
        );
    }

    function testGetHighestBid() public {
        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);
        uint256 bidAmount = 1 ether;
        vm.deal(address(this), bidAmount);
        auction.bid{value: bidAmount}();
        assertEq(auction.getHighestBid(), bidAmount);
    }

    function testGetAuctionEndTime() public view {
        assertEq(
            auction.getAuctionEndTime(),
            block.timestamp + AUCTION_DURATION
        );
    }

    function testGetBidsCount() public {
        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);
        auction.bid{value: 1 ether}();
        vm.warp(block.timestamp + auction.getCoolDownPeriod() + 1);
        auction.bid{value: 2 ether}();
        assertEq(auction.getBidsCount(), 2);
    }

    receive() external payable {}
}

contract MaliciousContract {
    receive() external payable {
        revert("Malicious contract");
    }
}
