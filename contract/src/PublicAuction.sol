// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PublicAuction is ReentrancyGuard, Ownable {
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }

    uint256 public auctionEndTime;
    uint256 public highestBid;
    address public highestBidder;
    mapping(address => uint256) public pendingReturns;
    bool public ended;

    // 出价冷却时间
    uint256 public constant COOL_DOWN_PERIOD = 5 minutes;
    // 时间加权出价奖励触发（距离结束拍卖的剩余时间）
    uint256 public constant TIME_WEIGHT_PERIOD = 5 minutes;
    // 时间加权出价奖励机制
    uint256 public constant TIME_WEIGHT_MULTIPLIER = 120; // 1.2x
    // 拍卖终局延长时间
    uint256 public constant AUCTION_EXTENSION_PERIOD = 5 minutes;

    mapping(address => uint256) public lastBidTime;

    Bid[] public bids;

    event HighestBidIncreased(address bidder, uint256 amount);
    event AuctionEnded(address winner, uint256 amount);
    event AuctionExtended(uint256 newEndTime);

    constructor(uint256 _biddingTime) Ownable(msg.sender) {
        auctionEndTime = block.timestamp + _biddingTime;
    }

    function bid() public payable nonReentrant {
        if (block.timestamp > auctionEndTime)
            revert PublicAuction__AuctionAlreadyEnded();

        if (msg.value <= highestBid)
            revert PublicAuction__BidNotHighEnough(highestBid);

        if (block.timestamp < lastBidTime[msg.sender] + COOL_DOWN_PERIOD)
            revert PublicAuction__BiddingCooldownNotExpired();

        uint256 weightedBid = msg.value;
        if (block.timestamp >= auctionEndTime - TIME_WEIGHT_PERIOD) {
            weightedBid = (msg.value * TIME_WEIGHT_MULTIPLIER) / 100;
        }

        if (highestBidder != address(0)) {
            pendingReturns[highestBidder] += highestBid;
        }

        highestBidder = msg.sender;
        highestBid = msg.value;
        // 用于计算出价冷却时间
        lastBidTime[msg.sender] = block.timestamp;

        bids.push(Bid(msg.sender, msg.value, block.timestamp));

        emit HighestBidIncreased(msg.sender, msg.value);

        // 如果距离拍卖结束时间小于AUCTION_EXTENSION_PERIOD，则延长拍卖时间
        if (block.timestamp > auctionEndTime - AUCTION_EXTENSION_PERIOD) {
            auctionEndTime = block.timestamp + AUCTION_EXTENSION_PERIOD;
            emit AuctionExtended(auctionEndTime);
        }
    }

    function withdraw() public nonReentrant returns (bool) {
        uint256 amount = pendingReturns[msg.sender];
        if (amount > 0) {
            pendingReturns[msg.sender] = 0;
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            if (!success) {
                pendingReturns[msg.sender] = amount;
                return false;
            }
        }
        return true;
    }

    function auctionEnd() public nonReentrant {
        if (block.timestamp < auctionEndTime)
            revert PublicAuction__AuctionNotYetEnded();
        if (ended) revert PublicAuction__AuctionEndAlreadyCalled();

        ended = true;
        emit AuctionEnded(highestBidder, highestBid);

        (bool success, ) = payable(owner()).call{value: highestBid}("");
        if (!success) revert PublicAuction__TransferFailed();
    }

    function getHighestBid() public view returns (uint256) {
        return highestBid;
    }

    function getAuctionEndTime() public view returns (uint256) {
        return auctionEndTime;
    }

    function getBidsCount() public view returns (uint256) {
        return bids.length;
    }

    function getCoolDownPeriod() public pure returns (uint256) {
        return COOL_DOWN_PERIOD;
    }

    error PublicAuction__AuctionAlreadyEnded();
    error PublicAuction__BidNotHighEnough(uint256 highestBid);
    error PublicAuction__BiddingCooldownNotExpired();
    error PublicAuction__AuctionNotYetEnded();
    error PublicAuction__AuctionEndAlreadyCalled();
    error PublicAuction__TransferFailed();
}
