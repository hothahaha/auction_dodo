// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PublicAuction.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PublicAuctionTest is Test {
    PublicAuction public auction;
    address public beneficiary;
    uint256 public constant AUCTION_DURATION = 1 days;
    string public constant DEFAULT_AUCTION_NAME = "Test Auction";
    string public constant DEFAULT_IPFS_HASH = "QmTest";

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
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
        );
        assertEq(auctionId, 0);
        assertEq(auction.nextAuctionId(), 1);

        (
            string memory name,
            uint256 startTime,
            uint256 endTime,
            address initiator,
            address highestBidder,
            uint256 highestBid,
            address auctionBeneficiary,
            bool ended,
            string memory ipfsHash
        ) = auction.auctions(auctionId);
        assertEq(name, DEFAULT_AUCTION_NAME);
        assertEq(endTime, startTime + AUCTION_DURATION);
        assertEq(initiator, address(this));
        assertEq(auctionBeneficiary, beneficiary);
        assertEq(highestBidder, address(0));
        assertEq(highestBid, 0);
        assertFalse(ended);
        assertEq(ipfsHash, DEFAULT_IPFS_HASH);
    }

    function testBidding() public {
        uint256 auctionId = auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
        );
        uint256 bidAmount = 1 ether;
        vm.deal(address(this), bidAmount);
        auction.bid{value: bidAmount}(auctionId);

        (
            ,
            ,
            ,
            ,
            address highestBidder,
            uint256 highestBid,
            ,
            bool ended,

        ) = auction.auctions(auctionId);
        assertEq(highestBid, bidAmount);
        assertEq(highestBidder, address(this));
        assertFalse(ended);
    }

    function testWithdraw() public {
        uint256 auctionId = auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
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

        // 结束拍卖
        vm.warp(block.timestamp + AUCTION_DURATION + 1 hours);
        auction.endAuction(auctionId);

        uint256 initialBalance = bidder1.balance;
        vm.prank(bidder1);
        auction.withdraw(auctionId);
        assertEq(bidder1.balance, initialBalance + bidAmount);
    }

    function testEndAuction() public {
        uint256 auctionId = auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
        );
        uint256 bidAmount = 1 ether;
        vm.deal(address(this), bidAmount);
        auction.bid{value: bidAmount}(auctionId);

        vm.warp(block.timestamp + AUCTION_DURATION + 1 hours);
        auction.endAuction(auctionId);

        (, , , , , , , bool ended, ) = auction.auctions(auctionId);
        assertTrue(ended);
        assertEq(beneficiary.balance, bidAmount);
    }

    function testGetAllBids() public {
        uint256 auctionId = auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
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
        auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            address(0),
            DEFAULT_IPFS_HASH
        );
    }

    function testCreateAuctionWithZeroDuration() public {
        vm.expectRevert(
            PublicAuction.PublicAuction__InvalidAuctionDuration.selector
        );
        auction.createAuction(
            DEFAULT_AUCTION_NAME,
            0,
            beneficiary,
            DEFAULT_IPFS_HASH
        );
    }

    function testBidOnNonExistentAuction() public {
        vm.expectRevert(PublicAuction.PublicAuction__AuctionNotFound.selector);
        auction.bid{value: 1 ether}(999);
    }

    function testBidAfterAuctionEnded() public {
        uint256 auctionId = auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
        );
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        vm.expectRevert(
            PublicAuction.PublicAuction__AuctionAlreadyEnded.selector
        );
        auction.bid{value: 1 ether}(auctionId);
    }

    function testWithdrawFromNotEndedAuction() public {
        vm.expectRevert(
            PublicAuction.PublicAuction__AuctionNotYetEnded.selector
        );
        auction.withdraw(999);
    }

    function testEndAuctionTwice() public {
        uint256 auctionId = auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
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
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            address(invalidBeneficiary),
            DEFAULT_IPFS_HASH
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
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
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

        // 结束拍卖
        vm.warp(block.timestamp + AUCTION_DURATION + 1 hours);
        auction.endAuction(auctionId);

        for (uint i = 0; i < bidders.length - 1; i++) {
            uint256 initialBalance = bidders[i].balance;
            vm.prank(bidders[i]);
            auction.withdraw(auctionId);
            assertEq(bidders[i].balance, initialBalance + (i + 1) * 1 ether);
        }

        (, , , , address highestBidder, uint256 highestBid, , , ) = auction
            .auctions(auctionId);
        assertEq(highestBidder, bidders[2]);
        assertEq(highestBid, 3 ether);
    }

    function testContractBalanceAfterBid() public {
        uint256 auctionId = auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
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

    function testGetBidsForAddress() public {
        uint256 auctionId = auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
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
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
        );
        vm.warp(block.timestamp + AUCTION_DURATION + 1 hours);
        auction.endAuction(auctionId);

        (
            ,
            ,
            ,
            ,
            address highestBidder,
            uint256 highestBid,
            ,
            bool ended,

        ) = auction.auctions(auctionId);
        assertEq(highestBidder, address(0));
        assertEq(highestBid, 0);
        assertTrue(ended);
    }

    function testMultipleBidsFromSameBidder() public {
        uint256 auctionId = auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
        );
        address bidder = address(0x1111);
        uint256 initialBidAmount = 1 ether;
        uint256 additionalBidAmount = 1 ether;

        vm.deal(bidder, initialBidAmount + additionalBidAmount);

        vm.prank(bidder);
        auction.bid{value: initialBidAmount}(auctionId);

        vm.prank(bidder);
        auction.bid{value: additionalBidAmount}(auctionId);

        (, , , , address highestBidder, uint256 highestBid, , , ) = auction
            .auctions(auctionId);
        assertEq(highestBidder, bidder);
        assertEq(highestBid, initialBidAmount + additionalBidAmount);
    }

    function testWithdrawAfterBeingOutbid() public {
        uint256 auctionId = auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
        );
        address bidder1 = address(0x1111);
        address bidder2 = address(0x2222);
        uint256 bidAmount1 = 1 ether;
        uint256 bidAmount2 = 2 ether;

        vm.deal(bidder1, bidAmount1);
        vm.prank(bidder1);
        auction.bid{value: bidAmount1}(auctionId);

        vm.deal(bidder2, bidAmount2);
        vm.prank(bidder2);
        auction.bid{value: bidAmount2}(auctionId);

        // 结束拍卖
        vm.warp(block.timestamp + AUCTION_DURATION + 1 hours);
        auction.endAuction(auctionId);

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

    function testCreateAuctionWithName() public {
        string memory auctionName = "Test Auction";
        string memory ipfsHash = "QmTest";
        uint256 auctionId = auction.createAuction(
            auctionName,
            AUCTION_DURATION,
            beneficiary,
            ipfsHash
        );

        assertEq(
            auction.getAuctionName(auctionId),
            auctionName,
            "Auction name should match"
        );
        assertEq(
            auction.getAuctionIPFSHash(auctionId),
            ipfsHash,
            "IPFS hash should match"
        );
    }

    function testGetAuctionName() public {
        string memory auctionName = "Rare Item Auction";
        string memory ipfsHash = "QmRare";
        uint256 auctionId = auction.createAuction(
            auctionName,
            AUCTION_DURATION,
            beneficiary,
            ipfsHash
        );

        string memory retrievedName = auction.getAuctionName(auctionId);
        assertEq(
            retrievedName,
            auctionName,
            "Retrieved auction name should match the created one"
        );
    }

    function testCreateAuctionWithEmptyName() public {
        vm.expectRevert(
            PublicAuction.PublicAuction__InvalidAuctionName.selector
        );
        auction.createAuction(
            "",
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
        );
    }

    function testGetAuctionNameNonExistentAuction() public {
        vm.expectRevert(PublicAuction.PublicAuction__AuctionNotFound.selector);
        auction.getAuctionName(999);
    }

    function testMultipleAuctionsWithDifferentNames() public {
        string[3] memory auctionNames = [
            "First Auction",
            "Second Auction",
            "Third Auction"
        ];
        uint256[] memory auctionIds = new uint256[](3);

        for (uint i = 0; i < auctionNames.length; i++) {
            auctionIds[i] = auction.createAuction(
                auctionNames[i],
                AUCTION_DURATION,
                beneficiary,
                string(abi.encodePacked("QmTest", i))
            );
        }

        for (uint i = 0; i < auctionNames.length; i++) {
            assertEq(
                auction.getAuctionName(auctionIds[i]),
                auctionNames[i],
                "Auction name should match"
            );
        }
    }

    function testCreateAuctionWithEmptyIPFSHash() public {
        vm.expectRevert(PublicAuction.PublicAuction__InvalidIPFSHash.selector);
        auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            ""
        );
    }

    function testGetAuctionIPFSHash() public {
        string memory ipfsHash = "QmRareItem";
        uint256 auctionId = auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            ipfsHash
        );

        string memory retrievedHash = auction.getAuctionIPFSHash(auctionId);
        assertEq(
            retrievedHash,
            ipfsHash,
            "Retrieved IPFS hash should match the created one"
        );
    }

    function testCreateAuctionWithInvalidName() public {
        vm.expectRevert(
            PublicAuction.PublicAuction__InvalidAuctionName.selector
        );
        auction.createAuction(
            "",
            AUCTION_DURATION,
            beneficiary,
            DEFAULT_IPFS_HASH
        );
    }

    function testCreateAuctionWithInvalidIPFSHash() public {
        vm.expectRevert(PublicAuction.PublicAuction__InvalidIPFSHash.selector);
        auction.createAuction(
            DEFAULT_AUCTION_NAME,
            AUCTION_DURATION,
            beneficiary,
            ""
        );
    }

    function testGetAuctionIdsByName() public {
        string memory auctionName = "Common Auction Name";
        uint256[] memory createdAuctionIds = new uint256[](3);

        for (uint i = 0; i < 3; i++) {
            createdAuctionIds[i] = auction.createAuction(
                auctionName,
                AUCTION_DURATION,
                beneficiary,
                string(abi.encodePacked("QmTest", i))
            );
        }

        uint256[] memory retrievedAuctionIds = auction.getAuctionIdsByName(
            auctionName
        );

        assertEq(
            retrievedAuctionIds.length,
            3,
            "Should retrieve 3 auction IDs"
        );
        for (uint i = 0; i < 3; i++) {
            assertEq(
                retrievedAuctionIds[i],
                createdAuctionIds[i],
                "Retrieved auction ID should match created ID"
            );
        }
    }

    function testGetAuctionIdsByNameNonExistent() public view {
        uint256[] memory retrievedAuctionIds = auction.getAuctionIdsByName(
            "Non-existent Auction"
        );
        assertEq(
            retrievedAuctionIds.length,
            0,
            "Should return an empty array for non-existent auction name"
        );
    }

    function testGetAuctionCount() public {
        uint256 initialCount = auction.getAuctionCount();

        for (uint i = 0; i < 3; i++) {
            auction.createAuction(
                string(abi.encodePacked("Auction ", i)),
                AUCTION_DURATION,
                beneficiary,
                string(abi.encodePacked("QmTest", i))
            );
        }

        uint256 finalCount = auction.getAuctionCount();
        assertEq(
            finalCount,
            initialCount + 3,
            "Auction count should increase by 3"
        );
    }

    // 在 PublicAuctionTest 合约中添加以下测试函数

    function testGetAuctionsByName() public {
        string memory auctionName = "Common Auction Name";
        uint256[] memory createdAuctionIds = new uint256[](3);

        for (uint i = 0; i < 3; i++) {
            createdAuctionIds[i] = auction.createAuction(
                auctionName,
                AUCTION_DURATION,
                beneficiary,
                string(abi.encodePacked("QmTest", i))
            );
        }

        PublicAuction.AuctionInfo[] memory auctionInfos = auction
            .getAuctionsByName(auctionName, 0, 10);

        assertEq(auctionInfos.length, 3, "Should retrieve 3 auctions");
        for (uint i = 0; i < 3; i++) {
            assertEq(
                auctionInfos[i].auctionId,
                createdAuctionIds[i],
                "Auction ID should match"
            );
            assertEq(
                auctionInfos[i].name,
                auctionName,
                "Auction name should match"
            );
            assertEq(
                auctionInfos[i].beneficiary,
                beneficiary,
                "Beneficiary should match"
            );
            assertEq(
                auctionInfos[i].ipfsHash,
                string(abi.encodePacked("QmTest", i)),
                "IPFS hash should match"
            );
        }
    }

    function testGetAuctionsByNameNonExistent() public view {
        PublicAuction.AuctionInfo[] memory auctionInfos = auction
            .getAuctionsByName("Non-existent Auction", 0, 10);
        assertEq(
            auctionInfos.length,
            0,
            "Should return an empty array for non-existent auction name"
        );
    }

    function testGetAllAuctionsWithEmptyName() public {
        // 创建多个拍卖
        string[3] memory auctionNames = ["Auction 1", "Auction 2", "Auction 3"];
        for (uint i = 0; i < auctionNames.length; i++) {
            auction.createAuction(
                auctionNames[i],
                AUCTION_DURATION,
                beneficiary,
                string(abi.encodePacked("QmTest", i))
            );
        }

        // 使用空字符串调用 getAuctionsByName
        PublicAuction.AuctionInfo[] memory allAuctions = auction
            .getAuctionsByName("", 0, 10);

        // 验证返回的拍卖数量
        assertEq(
            allAuctions.length,
            auctionNames.length,
            "Should return all auctions"
        );

        // 验证返回的拍卖信息
        for (uint i = 0; i < allAuctions.length; i++) {
            assertEq(
                allAuctions[i].name,
                auctionNames[i],
                "Auction name should match"
            );
            assertEq(allAuctions[i].auctionId, i, "Auction ID should match");
        }
    }

    function testGetAllAuctionsWithNullName() public {
        // 创建多个拍卖
        string[3] memory auctionNames = ["Auction A", "Auction B", "Auction C"];
        for (uint i = 0; i < auctionNames.length; i++) {
            auction.createAuction(
                auctionNames[i],
                AUCTION_DURATION,
                beneficiary,
                string(abi.encodePacked("QmTest", i))
            );
        }

        // 使用 null 调用 getAuctionsByName（在 Solidity 中，这等同于空字符串）
        PublicAuction.AuctionInfo[] memory allAuctions = auction
            .getAuctionsByName("", 0, 10);

        // 验证返回的拍卖数量
        assertEq(
            allAuctions.length,
            auctionNames.length,
            "Should return all auctions"
        );

        // 验证返回的拍卖信息
        for (uint i = 0; i < allAuctions.length; i++) {
            assertEq(
                allAuctions[i].name,
                auctionNames[i],
                "Auction name should match"
            );
            assertEq(allAuctions[i].auctionId, i, "Auction ID should match");
        }
    }

    function testGetAuctionsByNameWithPagination() public {
        string memory auctionName = "Common Auction Name";
        uint256 totalAuctions = 5;
        uint256[] memory createdAuctionIds = new uint256[](totalAuctions);

        for (uint i = 0; i < totalAuctions; i++) {
            createdAuctionIds[i] = auction.createAuction(
                auctionName,
                AUCTION_DURATION,
                beneficiary,
                string(abi.encodePacked("QmTest", i))
            );
        }

        // Test first page
        PublicAuction.AuctionInfo[] memory firstPage = auction
            .getAuctionsByName(auctionName, 0, 3);
        assertEq(firstPage.length, 3, "First page should have 3 auctions");
        for (uint i = 0; i < 3; i++) {
            assertEq(
                firstPage[i].auctionId,
                createdAuctionIds[i],
                "Auction ID should match"
            );
            assertEq(
                firstPage[i].name,
                auctionName,
                "Auction name should match"
            );
        }

        // Test second page
        PublicAuction.AuctionInfo[] memory secondPage = auction
            .getAuctionsByName(auctionName, 3, 3);
        assertEq(secondPage.length, 2, "Second page should have 2 auctions");
        for (uint i = 0; i < 2; i++) {
            assertEq(
                secondPage[i].auctionId,
                createdAuctionIds[i + 3],
                "Auction ID should match"
            );
            assertEq(
                secondPage[i].name,
                auctionName,
                "Auction name should match"
            );
        }

        // Test out of range
        PublicAuction.AuctionInfo[] memory emptyPage = auction
            .getAuctionsByName(auctionName, 5, 3);
        assertEq(
            emptyPage.length,
            0,
            "Out of range request should return empty array"
        );
    }

    function testGetAllAuctionsWithPagination() public {
        // Create multiple auctions
        string[5] memory auctionNames = [
            "Auction 1",
            "Auction 2",
            "Auction 3",
            "Auction 4",
            "Auction 5"
        ];
        for (uint i = 0; i < auctionNames.length; i++) {
            auction.createAuction(
                auctionNames[i],
                AUCTION_DURATION,
                beneficiary,
                string(abi.encodePacked("QmTest", i))
            );
        }

        // Test first page
        PublicAuction.AuctionInfo[] memory firstPage = auction
            .getAuctionsByName("", 0, 3);
        assertEq(firstPage.length, 3, "First page should have 3 auctions");
        for (uint i = 0; i < 3; i++) {
            assertEq(
                firstPage[i].name,
                auctionNames[i],
                "Auction name should match"
            );
            assertEq(firstPage[i].auctionId, i, "Auction ID should match");
        }

        // Test second page
        PublicAuction.AuctionInfo[] memory secondPage = auction
            .getAuctionsByName("", 3, 3);
        assertEq(secondPage.length, 2, "Second page should have 2 auctions");
        for (uint i = 0; i < 2; i++) {
            assertEq(
                secondPage[i].name,
                auctionNames[i + 3],
                "Auction name should match"
            );
            assertEq(secondPage[i].auctionId, i + 3, "Auction ID should match");
        }

        // Test out of range
        PublicAuction.AuctionInfo[] memory emptyPage = auction
            .getAuctionsByName("", 5, 3);
        assertEq(
            emptyPage.length,
            0,
            "Out of range request should return empty array"
        );
    }

    function testGetAuctionCountByName() public {
        string memory commonName = "Common Auction";
        string memory uniqueName = "Unique Auction";

        // Create multiple auctions with common name
        for (uint i = 0; i < 3; i++) {
            auction.createAuction(
                commonName,
                AUCTION_DURATION,
                beneficiary,
                string(abi.encodePacked("QmTest", i))
            );
        }

        // Create one auction with unique name
        auction.createAuction(
            uniqueName,
            AUCTION_DURATION,
            beneficiary,
            "QmTestUnique"
        );

        uint256 commonCount = auction.getAuctionCountByName(commonName);
        assertEq(commonCount, 3, "Should return correct count for common name");

        uint256 uniqueCount = auction.getAuctionCountByName(uniqueName);
        assertEq(uniqueCount, 1, "Should return correct count for unique name");

        uint256 nonExistentCount = auction.getAuctionCountByName(
            "Non-existent"
        );
        assertEq(
            nonExistentCount,
            0,
            "Should return zero for non-existent name"
        );

        uint256 totalCount = auction.getAuctionCountByName("");
        assertEq(totalCount, 4, "Should return total count for empty string");
    }
}

// 添加这个新的合约在测试合约之外
contract RevertingContract {
    receive() external payable {
        revert("Always reverts");
    }
}
