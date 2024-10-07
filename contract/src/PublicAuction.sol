// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

/// @title 公开拍卖
/// @notice 此合约实现了一个可升级的公开拍卖系统，支持多个拍卖和IPFS图片上传
/// @dev 使用OpenZeppelin的可升级合约并实现UUPS代理模式
contract PublicAuction is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    AutomationCompatibleInterface
{
    // Type declarations
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 bidTime;
    }

    struct Auction {
        string name;
        uint256 startTime;
        uint256 endTime;
        address initiator;
        address highestBidder;
        uint256 highestBid;
        address beneficiary;
        bool ended;
        string ipfsHash;
        Bid[] bids;
        mapping(address => uint256) bidderTotalAmount;
    }

    struct AuctionInfo {
        uint256 auctionId;
        string name;
        uint256 startTime;
        uint256 endTime;
        address initiator;
        address highestBidder;
        uint256 highestBid;
        address beneficiary;
        bool ended;
        string ipfsHash;
        Bid[] bids;
    }

    // State variables
    uint256 public nextAuctionId;
    mapping(uint256 => Auction) public auctions;
    mapping(string => uint256[]) private s_auctionsByName;

    // Events
    event AuctionCreated(
        uint256 indexed auctionId,
        string name,
        address initiator,
        uint256 startTime,
        uint256 endTime,
        string ipfsHash
    );
    event BidPlaced(
        uint256 indexed auctionId,
        address bidder,
        uint256 amount,
        uint256 newHighestBid
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
    error PublicAuction__AuctionNotYetEnded();
    error PublicAuction__AuctionEndAlreadyCalled();
    error PublicAuction__AuctionNotYetEndedOrInBuffer();
    error PublicAuction__TransferFailed();
    error PublicAuction__InvalidAuctionDuration();
    error PublicAuction__AuctionNotFound();
    error PublicAuction__InsufficientContractBalance();
    error PublicAuction__InvalidIPFSHash();
    error PublicAuction__InvalidAuctionName();
    error PublicAuction__UpkeepNotNeeded(
        uint256 balance,
        uint256 bidderLength,
        bool auctionState
    );

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
    /// @param _name 拍卖名称
    /// @param _duration 拍卖持续时间（以秒为单位）
    /// @param _beneficiary 接收最高出价的地址
    /// @param _ipfsHash IPFS哈希，指向拍卖物品的图片
    function createAuction(
        string memory _name,
        uint256 _duration,
        address _beneficiary,
        string memory _ipfsHash
    ) public returns (uint256) {
        if (_beneficiary == address(0))
            revert PublicAuction__BeneficiaryCannotBeZeroAddress();
        if (_duration == 0) revert PublicAuction__InvalidAuctionDuration();
        if (bytes(_ipfsHash).length == 0)
            revert PublicAuction__InvalidIPFSHash();
        if (bytes(_name).length == 0)
            revert PublicAuction__InvalidAuctionName();

        uint256 auctionId = nextAuctionId++;
        Auction storage newAuction = auctions[auctionId];
        newAuction.name = _name;
        newAuction.startTime = block.timestamp;
        newAuction.endTime = block.timestamp + _duration;
        newAuction.initiator = msg.sender;
        newAuction.beneficiary = _beneficiary;
        newAuction.ended = false;
        newAuction.ipfsHash = _ipfsHash;

        s_auctionsByName[_name].push(auctionId);

        emit AuctionCreated(
            auctionId,
            _name,
            msg.sender,
            newAuction.startTime,
            newAuction.endTime,
            _ipfsHash
        );
        return auctionId;
    }

    /// @notice 对特定拍卖进行加价
    /// @param _auctionId 拍卖ID
    function bid(uint256 _auctionId) public payable nonReentrant {
        Auction storage auction = auctions[_auctionId];
        if (auction.startTime == 0) revert PublicAuction__AuctionNotFound();
        if (block.timestamp > auction.endTime)
            revert PublicAuction__AuctionAlreadyEnded();

        uint256 newBidAmount = auction.bidderTotalAmount[msg.sender] +
            msg.value;
        auction.bidderTotalAmount[msg.sender] = newBidAmount;

        if (newBidAmount > auction.highestBid) {
            auction.highestBidder = msg.sender;
            auction.highestBid = newBidAmount;
        }

        auction.bids.push(Bid(msg.sender, msg.value, block.timestamp));

        emit BidPlaced(_auctionId, msg.sender, msg.value, auction.highestBid);
    }

    function endAuction(uint256 _auctionId) public {
        _endAuction(_auctionId);
    }

    // External functions
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        for (uint256 i = 0; i < nextAuctionId; i++) {
            Auction storage auction = auctions[i];
            if (
                !auction.ended &&
                block.timestamp > auction.endTime &&
                address(this).balance > 0 &&
                auction.bids.length > 0
            ) {
                return (true, abi.encode(i));
            }
        }
        return (false, bytes(""));
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256 auctionId = abi.decode(performData, (uint256));
        Auction storage auction = auctions[auctionId];

        if (
            auction.ended ||
            block.timestamp <= auction.endTime ||
            address(this).balance == 0 ||
            auction.bids.length == 0
        ) {
            revert PublicAuction__UpkeepNotNeeded(
                address(this).balance,
                auction.bids.length,
                auction.ended
            );
        }

        _endAuction(auctionId);
    }

    // Public view functions
    /// @notice 返回特定拍卖中所有价
    /// @param _auctionId 拍卖ID
    /// @return 所有出价的数组
    function getAllBids(uint256 _auctionId) public view returns (Bid[] memory) {
        return auctions[_auctionId].bids;
    }

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

    /// @notice 获取拍卖的IPFS哈希
    /// @param _auctionId 拍卖ID
    /// @return IPFS哈希
    function getAuctionIPFSHash(
        uint256 _auctionId
    ) public view returns (string memory) {
        if (auctions[_auctionId].startTime == 0)
            revert PublicAuction__AuctionNotFound();
        return auctions[_auctionId].ipfsHash;
    }

    /// @notice 获取拍卖名称
    /// @param _auctionId 拍卖ID
    /// @return 拍卖名称
    function getAuctionName(
        uint256 _auctionId
    ) public view returns (string memory) {
        if (auctions[_auctionId].startTime == 0)
            revert PublicAuction__AuctionNotFound();
        return auctions[_auctionId].name;
    }

    /// @notice 根据拍卖名称查询拍卖ID
    /// @param _name 拍卖名称
    /// @return 匹配名称的拍卖ID数组
    function getAuctionIdsByName(
        string memory _name
    ) public view returns (uint256[] memory) {
        return s_auctionsByName[_name];
    }

    /// @notice 根据拍卖名称查询匹配的所有拍卖信息，如果名称为空则返回所有拍卖（带分页）
    /// @param _name 拍卖名称，如果为空字符串则返回所有拍卖
    /// @param _offset 起始位置
    /// @param _limit 返回的最大数量
    /// @return 匹配名称的拍卖信息数组，或所有拍卖信息（分页）
    function getAuctionsByName(
        string memory _name,
        uint256 _offset,
        uint256 _limit
    ) public view returns (AuctionInfo[] memory) {
        uint256[] memory auctionIds;
        uint256 totalCount;

        if (bytes(_name).length == 0) {
            totalCount = nextAuctionId;
            auctionIds = new uint256[](totalCount);
            for (uint256 i = 0; i < totalCount; i++) {
                auctionIds[i] = i;
            }
        } else {
            auctionIds = s_auctionsByName[_name];
            totalCount = auctionIds.length;
        }

        uint256 endIndex = _offset + _limit > totalCount
            ? totalCount
            : _offset + _limit;
        uint256 resultCount = endIndex > _offset ? endIndex - _offset : 0;

        AuctionInfo[] memory result = new AuctionInfo[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            uint256 auctionId = auctionIds[_offset + i];
            Auction storage auction = auctions[auctionId];
            result[i] = AuctionInfo({
                auctionId: auctionId,
                name: auction.name,
                startTime: auction.startTime,
                endTime: auction.endTime,
                initiator: auction.initiator,
                highestBidder: auction.highestBidder,
                highestBid: auction.highestBid,
                beneficiary: auction.beneficiary,
                ended: auction.ended,
                ipfsHash: auction.ipfsHash,
                bids: auction.bids
            });
        }

        return result;
    }

    /// @notice 获取符合条件的拍卖总数
    /// @param _name 拍卖名称，如果为空字符串则返回所有拍卖数量
    /// @return 符合条件的拍卖总数
    function getAuctionCountByName(
        string memory _name
    ) public view returns (uint256) {
        if (bytes(_name).length == 0) {
            return nextAuctionId;
        } else {
            return s_auctionsByName[_name].length;
        }
    }

    // 添加 withdraw 函数
    function withdraw(uint256 _auctionId) public nonReentrant {
        Auction storage auction = auctions[_auctionId];
        if (!auction.ended) {
            revert PublicAuction__AuctionNotYetEnded();
        }
        uint256 amount = auction.bidderTotalAmount[msg.sender];
        if (msg.sender != auction.highestBidder) {
            auction.bidderTotalAmount[msg.sender] = 0;
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            if (!success) revert PublicAuction__TransferFailed();
            emit WithdrawSuccessful(_auctionId, msg.sender, amount);
        }
    }

    /// @notice 获取所有拍卖的数量
    /// @return 拍卖总数
    function getAuctionCount() public view returns (uint256) {
        return nextAuctionId;
    }

    // Internal functions
    function _endAuction(uint256 _auctionId) internal {
        Auction storage auction = auctions[_auctionId];
        if (auction.startTime == 0) revert PublicAuction__AuctionNotFound();
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

    /// @notice 内部函数，用于授权升级
    /// @dev 只能由合约所有者调用
    /// @param newImplementation 新实现的地址
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
