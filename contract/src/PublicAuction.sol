// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Public Auction Contract
/// @notice Implements a public auction with time-weighted bidding and extension mechanisms
contract PublicAuction is ReentrancyGuard, Ownable {
    // Custom Errors
    error PublicAuction__AuctionAlreadyEnded();
    error PublicAuction__BidNotHighEnough(uint256 highestBid);
    error PublicAuction__BiddingCooldownNotExpired();
    error PublicAuction__AuctionNotYetEnded();
    error PublicAuction__AuctionEndAlreadyCalled();
    error PublicAuction__TransferFailed();

    // Structs
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }

    // State Variables
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

    // Events
    event HighestBidIncreased(address bidder, uint256 amount);
    event AuctionEnded(address winner, uint256 amount);
    event AuctionExtended(uint256 newEndTime);

    /// @notice Creates a new auction with the specified bidding time
    /// @param _biddingTime Duration of the auction in seconds
    constructor(uint256 _biddingTime) Ownable(msg.sender) {
        auctionEndTime = block.timestamp + _biddingTime;
    }

    /// @notice Place a bid on the auction
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
        highestBid = weightedBid;
        lastBidTime[msg.sender] = block.timestamp;

        bids.push(Bid(msg.sender, weightedBid, block.timestamp));

        emit HighestBidIncreased(msg.sender, weightedBid);

        if (block.timestamp > auctionEndTime - AUCTION_EXTENSION_PERIOD) {
            auctionEndTime = block.timestamp + AUCTION_EXTENSION_PERIOD;
            emit AuctionExtended(auctionEndTime);
        }
    }

    /// @notice Withdraw a previous bid that was overbid
    /// @return success Whether the withdrawal was successful
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

    /// @notice End the auction and send the highest bid to the owner
    function auctionEnd() public nonReentrant {
        if (block.timestamp < auctionEndTime)
            revert PublicAuction__AuctionNotYetEnded();
        if (ended) revert PublicAuction__AuctionEndAlreadyCalled();

        ended = true;
        emit AuctionEnded(highestBidder, highestBid);

        (bool success, ) = payable(owner()).call{value: highestBid}("");
        if (!success) revert PublicAuction__TransferFailed();
    }

    // View/Pure Functions
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
}
