// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract PublicAuction is ReentrancyGuard, Pausable, Ownable {
    using SafeMath for uint256;

    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }

    address payable public seller;
    uint256 public auctionEndTime;
    uint256 public highestBid;
    address public highestBidder;
    mapping(address => uint256) public pendingReturns;
    bool public ended;

    uint256 public constant COOL_DOWN_PERIOD = 5 minutes;
    uint256 public constant TIME_WEIGHT_PERIOD = 5 minutes;
    uint256 public constant TIME_WEIGHT_MULTIPLIER = 120; // 1.2x
    uint256 public constant AUCTION_EXTENSION_PERIOD = 5 minutes;

    mapping(address => uint256) public lastBidTime;

    Bid[] public bids;

    event HighestBidIncreased(address bidder, uint256 amount);
    event AuctionEnded(address winner, uint256 amount);
    event AuctionExtended(uint256 newEndTime);

    constructor(uint256 _biddingTime, address payable _seller) {
        seller = _seller;
        auctionEndTime = block.timestamp + _biddingTime;
    }

    function bid() public payable nonReentrant whenNotPaused {
        if (block.timestamp > auctionEndTime)
            revert PublicAuction__AuctionAlreadyEnded();

        if (msg.value <= highestBid)
            revert PublicAuction__BidNotHighEnough(highestBid);

        if (block.timestamp < lastBidTime[msg.sender] + COOL_DOWN_PERIOD)
            revert PublicAuction__BiddingCooldownNotExpired();

        uint256 weightedBid = msg.value;
        if (block.timestamp >= auctionEndTime - TIME_WEIGHT_PERIOD) {
            weightedBid = msg.value.mul(TIME_WEIGHT_MULTIPLIER).div(100);
        }

        if (highestBidder != address(0)) {
            pendingReturns[highestBidder] += highestBid;
        }

        highestBidder = msg.sender;
        highestBid = msg.value;
        lastBidTime[msg.sender] = block.timestamp;

        bids.push(Bid(msg.sender, msg.value, block.timestamp));

        emit HighestBidIncreased(msg.sender, msg.value);

        if (block.timestamp > auctionEndTime - AUCTION_EXTENSION_PERIOD) {
            auctionEndTime = block.timestamp + AUCTION_EXTENSION_PERIOD;
            emit AuctionExtended(auctionEndTime);
        }
    }

    function withdraw() public nonReentrant returns (bool) {
        uint256 amount = pendingReturns[msg.sender];
        if (amount > 0) {
            pendingReturns[msg.sender] = 0;
            if (!payable(msg.sender).send(amount)) {
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

        seller.transfer(highestBid);
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

    error PublicAuction__AuctionAlreadyEnded();
    error PublicAuction__BidNotHighEnough(uint256 highestBid);
    error PublicAuction__BiddingCooldownNotExpired();
    error PublicAuction__AuctionNotYetEnded();
    error PublicAuction__AuctionEndAlreadyCalled();
}
