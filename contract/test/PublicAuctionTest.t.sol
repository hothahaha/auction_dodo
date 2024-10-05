// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PublicAuction.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PublicAuctionTest is Test {
    PublicAuction public auction;
    address public beneficiary;
    uint256 public constant AUCTION_DURATION = 1 days;

    function setUp() public {
        beneficiary = address(0x1234);
        PublicAuction implementation = new PublicAuction();

        bytes memory data = abi.encodeWithSelector(
            PublicAuction.initialize.selector
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        auction = PublicAuction(address(proxy));
    }

    function testInitialState() public view {
        assertEq(auction.nextAuctionId(), 0);
    }

    function testCreateAuction() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        assertEq(auctionId, 0);
        assertEq(auction.nextAuctionId(), 1);

        (
            uint256 startTime,
            uint256 endTime,
            address initiator,
            address highestBidder,
            uint256 highestBid,
            address auctionBeneficiary,
            bool ended
        ) = auction.auctions(auctionId);
        assertEq(endTime, startTime + AUCTION_DURATION);
        assertEq(initiator, address(this));
        assertEq(auctionBeneficiary, beneficiary);
        assertEq(highestBidder, address(0));
        assertEq(highestBid, 0);
        assertFalse(ended);
    }

    function testBidding() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        uint256 bidAmount = 1 ether;
        vm.deal(address(this), bidAmount);
        auction.bid{value: bidAmount}(auctionId);

        (
            ,
            ,
            ,
            address highestBidder,
            uint256 highestBid,
            ,
            bool ended
        ) = auction.auctions(auctionId);
        assertEq(highestBid, bidAmount);
        assertEq(highestBidder, address(this));
        assertFalse(ended);
    }

    function testFailBidTooLow() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        uint256 bidAmount = 1 ether;
        vm.deal(address(this), bidAmount * 2);
        auction.bid{value: bidAmount}(auctionId);

        vm.prank(address(0x5678));
        vm.expectRevert(
            abi.encodeWithSelector(
                PublicAuction.PublicAuction__BidNotHighEnough.selector,
                bidAmount
            )
        );
        auction.bid{value: bidAmount}(auctionId);
    }

    function testWithdraw() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        uint256 bidAmount = 1 ether;
        address bidder1 = address(0x1111);
        address bidder2 = address(0x2222);

        vm.deal(bidder1, bidAmount);
        vm.prank(bidder1);
        auction.bid{value: bidAmount}(auctionId);

        vm.deal(bidder2, bidAmount * 2);
        vm.prank(bidder2);
        auction.bid{value: bidAmount * 2}(auctionId);

        uint256 initialBalance = bidder1.balance;
        vm.prank(bidder1);
        auction.withdraw(auctionId);
        assertEq(bidder1.balance, initialBalance + bidAmount);
    }

    function testEndAuction() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        uint256 bidAmount = 1 ether;
        vm.deal(address(this), bidAmount);
        auction.bid{value: bidAmount}(auctionId);

        vm.warp(block.timestamp + AUCTION_DURATION + 1 hours);
        auction.endAuction(auctionId);

        (, , , , , , bool ended) = auction.auctions(auctionId);
        assertTrue(ended);
        assertEq(beneficiary.balance, bidAmount);
    }

    function testEndAuctionTooEarly() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        vm.expectRevert(
            PublicAuction.PublicAuction__AuctionNotYetEndedOrInBuffer.selector
        );
        auction.endAuction(auctionId);
    }

    function testGetAllBids() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        uint256 bidAmount1 = 1 ether;
        uint256 bidAmount2 = 2 ether;

        vm.deal(address(this), bidAmount1);
        auction.bid{value: bidAmount1}(auctionId);

        vm.deal(address(0x5678), bidAmount2);
        vm.prank(address(0x5678));
        auction.bid{value: bidAmount2}(auctionId);

        PublicAuction.Bid[] memory bids = auction.getAllBids(auctionId);
        assertEq(bids.length, 2);
        assertEq(bids[0].bidder, address(this));
        assertEq(bids[0].amount, bidAmount1);
        assertEq(bids[1].bidder, address(0x5678));
        assertEq(bids[1].amount, bidAmount2);
    }

    // 在现有测试之后添加以下测试函数

    function testCreateAuctionWithZeroBeneficiary() public {
        vm.expectRevert(
            PublicAuction.PublicAuction__BeneficiaryCannotBeZeroAddress.selector
        );
        auction.createAuction(AUCTION_DURATION, address(0));
    }

    function testCreateAuctionWithZeroDuration() public {
        vm.expectRevert(
            PublicAuction.PublicAuction__InvalidAuctionDuration.selector
        );
        auction.createAuction(0, beneficiary);
    }

    function testBidOnNonExistentAuction() public {
        vm.expectRevert(PublicAuction.PublicAuction__AuctionNotFound.selector);
        auction.bid{value: 1 ether}(999);
    }

    function testBidAfterAuctionEnded() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        vm.expectRevert(
            PublicAuction.PublicAuction__AuctionAlreadyEnded.selector
        );
        auction.bid{value: 1 ether}(auctionId);
    }

    function testWithdrawFromNonExistentAuction() public {
        vm.expectRevert(PublicAuction.PublicAuction__AuctionNotFound.selector);
        auction.withdraw(999);
    }

    function testEndNonExistentAuction() public {
        vm.expectRevert(PublicAuction.PublicAuction__AuctionNotFound.selector);
        auction.endAuction(999);
    }

    function testEndAuctionTwice() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        vm.warp(block.timestamp + AUCTION_DURATION + 1 hours);
        auction.endAuction(auctionId);
        vm.expectRevert(
            PublicAuction.PublicAuction__AuctionEndAlreadyCalled.selector
        );
        auction.endAuction(auctionId);
    }

    function testTransferToInvalidBeneficiary() public {
        RevertingContract invalidBeneficiary = new RevertingContract();
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            address(invalidBeneficiary)
        );
        uint256 bidAmount = 1 ether;
        vm.deal(address(this), bidAmount);
        auction.bid{value: bidAmount}(auctionId);

        vm.warp(block.timestamp + AUCTION_DURATION + 1 hours);
        vm.expectRevert(PublicAuction.PublicAuction__TransferFailed.selector);
        auction.endAuction(auctionId);
    }

    function testMultipleBidsAndWithdraws() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        address[] memory bidders = new address[](3);
        bidders[0] = address(0x1111);
        bidders[1] = address(0x2222);
        bidders[2] = address(0x3333);

        for (uint i = 0; i < bidders.length; i++) {
            uint256 bidAmount = (i + 1) * 1 ether;
            vm.deal(bidders[i], bidAmount);
            vm.prank(bidders[i]);
            auction.bid{value: bidAmount}(auctionId);
        }

        for (uint i = 0; i < bidders.length - 1; i++) {
            uint256 initialBalance = bidders[i].balance;
            vm.prank(bidders[i]);
            auction.withdraw(auctionId);
            assertEq(bidders[i].balance, initialBalance + (i + 1) * 1 ether);
        }

        (, , , address highestBidder, uint256 highestBid, , ) = auction
            .auctions(auctionId);
        assertEq(highestBidder, bidders[2]);
        assertEq(highestBid, 3 ether);
    }

    function testContractBalanceAfterBid() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        uint256 bidAmount = 1 ether;

        address bidder = address(0x1234);
        vm.deal(bidder, bidAmount);

        uint256 initialContractBalance = address(auction).balance;

        vm.prank(bidder);
        auction.bid{value: bidAmount}(auctionId);

        uint256 finalContractBalance = address(auction).balance;
        assertEq(
            finalContractBalance,
            initialContractBalance + bidAmount,
            "Contract balance should increase by bid amount"
        );
    }

    // 在现有测试之后添加以下测试函数

    function testBidWithZeroValue() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PublicAuction.PublicAuction__BidNotHighEnough.selector,
                0 // 当前的最高出价
            )
        );
        auction.bid{value: 0}(auctionId);
    }

    function testWithdrawWithNoPendingReturns() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        bool success = auction.withdraw(auctionId);
        assertTrue(success);
    }

    function testGetBidsForAddress() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        address bidder = address(0x1234);
        uint256 bidAmount = 1 ether;

        vm.deal(bidder, bidAmount * 3);
        vm.prank(bidder);
        auction.bid{value: bidAmount}(auctionId);

        vm.prank(bidder);
        auction.bid{value: bidAmount * 2}(auctionId);

        PublicAuction.Bid[] memory bids = auction.getBidsForAddress(
            auctionId,
            bidder
        );
        assertEq(bids.length, 2);
        assertEq(bids[0].amount, bidAmount);
        assertEq(bids[1].amount, bidAmount * 2);
    }

    function testGetBidsForAddressNonExistentAuction() public {
        vm.expectRevert(PublicAuction.PublicAuction__AuctionNotFound.selector);
        auction.getBidsForAddress(999, address(0x1234));
    }

    function testEndAuctionWithNoHighestBidder() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        vm.warp(block.timestamp + AUCTION_DURATION + 1 hours);
        auction.endAuction(auctionId);

        (
            ,
            ,
            ,
            address highestBidder,
            uint256 highestBid,
            ,
            bool ended
        ) = auction.auctions(auctionId);
        assertEq(highestBidder, address(0));
        assertEq(highestBid, 0);
        assertTrue(ended);
    }

    function testMultipleBidsFromSameBidder() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        address bidder = address(0x1234);
        uint256 initialBidAmount = 1 ether;

        vm.deal(bidder, initialBidAmount * 3);

        vm.prank(bidder);
        auction.bid{value: initialBidAmount}(auctionId);

        vm.prank(bidder);
        auction.bid{value: initialBidAmount * 2}(auctionId);

        (, , , address highestBidder, uint256 highestBid, , ) = auction
            .auctions(auctionId);
        assertEq(highestBidder, bidder);
        assertEq(highestBid, initialBidAmount * 2);

        PublicAuction.Bid[] memory bids = auction.getBidsForAddress(
            auctionId,
            bidder
        );
        assertEq(bids.length, 2);
    }

    function testWithdrawAfterBeingOutbid() public {
        uint256 auctionId = auction.createAuction(
            AUCTION_DURATION,
            beneficiary
        );
        address bidder1 = address(0x1234);
        address bidder2 = address(0x5678);
        uint256 bidAmount1 = 1 ether;
        uint256 bidAmount2 = 2 ether;

        vm.deal(bidder1, bidAmount1);
        vm.prank(bidder1);
        auction.bid{value: bidAmount1}(auctionId);

        vm.deal(bidder2, bidAmount2);
        vm.prank(bidder2);
        auction.bid{value: bidAmount2}(auctionId);

        uint256 initialBalance = bidder1.balance;
        vm.prank(bidder1);
        auction.withdraw(auctionId);
        assertEq(bidder1.balance, initialBalance + bidAmount1);
    }

    function testFailAuthorizeUpgradeNonOwner() public {
        address newImplementation = address(0x1234);
        vm.prank(address(0x5678));
        vm.expectRevert("Ownable: caller is not the owner");
        auction.upgradeToAndCall(newImplementation, "");
    }
}

// 添加这个新的合约在测试合约之外
contract RevertingContract {
    receive() external payable {
        revert("Always reverts");
    }
}
