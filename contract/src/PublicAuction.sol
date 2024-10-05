// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @title 公开拍卖
/// @notice 此合约实现了一个可升级的公开拍卖系统，支持多个拍卖
/// @dev 使用OpenZeppelin的可升级合约并实现UUPS代理模式
contract PublicAuction is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // Structs
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 bidTime;
        bool withdrawn;
    }

    struct Auction {
        uint256 startTime;
        uint256 endTime;
        address initiator;
        address highestBidder;
        uint256 highestBid;
        address beneficiary;
        bool ended;
        Bid[] bids;
        mapping(address => uint256) pendingReturns;
    }

    // State Variables
    uint256 public nextAuctionId;
    mapping(uint256 => Auction) public auctions;

    // Events
    event AuctionCreated(
        uint256 indexed auctionId,
        address initiator,
        uint256 startTime,
        uint256 endTime
    );
    event HighestBidIncreased(
        uint256 indexed auctionId,
        address bidder,
        uint256 amount
    );
    event AuctionEnded(
        uint256 indexed auctionId,
        address winner,
        uint256 amount
    );
    event WithdrawSuccessful(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );

    // Errors
    error PublicAuction__BeneficiaryCannotBeZeroAddress();
    error PublicAuction__AuctionAlreadyEnded();
    error PublicAuction__BidNotHighEnough(uint256 highestBid);
    error PublicAuction__AuctionNotYetEnded();
    error PublicAuction__AuctionEndAlreadyCalled();
    error PublicAuction__AuctionNotYetEndedOrInBuffer();
    error PublicAuction__TransferFailed();
    error PublicAuction__InvalidAuctionDuration();
    error PublicAuction__AuctionNotFound();
    error PublicAuction__InsufficientContractBalance();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice 初始化拍卖合约
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        nextAuctionId = 0;
    }

    /// @notice 创建新的拍卖
    /// @param _duration 拍卖持续时间（以秒为单位）
    /// @param _beneficiary 接收最高出价的地址
    function createAuction(
        uint256 _duration,
        address _beneficiary
    ) public returns (uint256) {
        if (_beneficiary == address(0))
            revert PublicAuction__BeneficiaryCannotBeZeroAddress();
        if (_duration == 0) revert PublicAuction__InvalidAuctionDuration();

        uint256 auctionId = nextAuctionId++;
        Auction storage newAuction = auctions[auctionId];
        newAuction.startTime = block.timestamp;
        newAuction.endTime = block.timestamp + _duration;
        newAuction.initiator = msg.sender;
        newAuction.beneficiary = _beneficiary;
        newAuction.ended = false;

        emit AuctionCreated(
            auctionId,
            msg.sender,
            newAuction.startTime,
            newAuction.endTime
        );
        return auctionId;
    }

    /// @notice 对特定拍卖进行竞价
    /// @param _auctionId 拍卖ID
    function bid(uint256 _auctionId) public payable nonReentrant {
        Auction storage auction = auctions[_auctionId];
        if (auction.startTime == 0) revert PublicAuction__AuctionNotFound();
        if (block.timestamp > auction.endTime)
            revert PublicAuction__AuctionAlreadyEnded();
        if (msg.value <= auction.highestBid)
            revert PublicAuction__BidNotHighEnough(auction.highestBid);

        if (auction.highestBid != 0) {
            auction.pendingReturns[auction.highestBidder] += auction.highestBid;
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;
        auction.bids.push(Bid(msg.sender, msg.value, block.timestamp, false));

        emit HighestBidIncreased(_auctionId, msg.sender, msg.value);
    }

    /// @notice 允许出价者从特定拍卖中提取他们的超额出价
    /// @param _auctionId 拍卖ID
    function withdraw(uint256 _auctionId) public nonReentrant returns (bool) {
        Auction storage auction = auctions[_auctionId];
        if (auction.startTime == 0) revert PublicAuction__AuctionNotFound();

        uint256 amount = auction.pendingReturns[msg.sender];
        if (amount > 0) {
            auction.pendingReturns[msg.sender] = 0;

            (bool success, ) = payable(msg.sender).call{value: amount}("");
            if (!success) {
                auction.pendingReturns[msg.sender] = amount;
                return false;
            }

            // 更新相应的 Bid 状态
            for (uint i = 0; i < auction.bids.length; i++) {
                if (
                    auction.bids[i].bidder == msg.sender &&
                    !auction.bids[i].withdrawn
                ) {
                    auction.bids[i].withdrawn = true;
                    break;
                }
            }

            emit WithdrawSuccessful(_auctionId, msg.sender, amount);
        }
        return true;
    }

    /// @notice 结束特定拍卖并将最高出价发送给受益人
    /// @param _auctionId 拍卖ID
    function endAuction(uint256 _auctionId) public {
        Auction storage auction = auctions[_auctionId];
        if (auction.startTime == 0) revert PublicAuction__AuctionNotFound();
        if (block.timestamp < auction.endTime + 1 hours)
            revert PublicAuction__AuctionNotYetEndedOrInBuffer();
        if (auction.ended) revert PublicAuction__AuctionEndAlreadyCalled();

        auction.ended = true;
        uint256 finalBid = auction.highestBid;
        address winner = auction.highestBidder;

        emit AuctionEnded(_auctionId, winner, finalBid);

        if (address(this).balance < finalBid)
            revert PublicAuction__InsufficientContractBalance();

        (bool success, ) = payable(auction.beneficiary).call{value: finalBid}(
            ""
        );
        if (!success) revert PublicAuction__TransferFailed();
    }

    /// @notice 返回特定拍卖中所有出价
    /// @param _auctionId 拍卖ID
    /// @return 所有出价的数组
    function getAllBids(uint256 _auctionId) public view returns (Bid[] memory) {
        return auctions[_auctionId].bids;
    }

    /// @notice 内部函数，用于授权升级
    /// @dev 只能由合约所有者调用
    /// @param newImplementation 新实现的地址
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /// @notice 获取某个拍卖中特定地址的所有出价
    /// @param _auctionId 拍卖ID
    /// @param _bidder 地址
    /// @return 所有出价的数组
    function getBidsForAddress(
        uint256 _auctionId,
        address _bidder
    ) public view returns (Bid[] memory) {
        Auction storage auction = auctions[_auctionId];
        if (auction.startTime == 0) revert PublicAuction__AuctionNotFound();

        uint256 bidCount = 0;
        for (uint i = 0; i < auction.bids.length; i++) {
            if (auction.bids[i].bidder == _bidder) {
                bidCount++;
            }
        }

        Bid[] memory result = new Bid[](bidCount);
        uint256 index = 0;
        for (uint i = 0; i < auction.bids.length; i++) {
            if (auction.bids[i].bidder == _bidder) {
                result[index] = auction.bids[i];
                index++;
            }
        }

        return result;
    }
}
