// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract AssetManagement is ReentrancyGuard {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private _assetIds;
    Counters.Counter private _bundleIds;
    Counters.Counter private _auctionIds;
    Counters.Counter private _rentalIds;

    enum AssetStatus { Active, Locked, InAuction, Rented, Burned }

    struct Asset {
        uint256 id;
        string name;
        uint256 value;
        address owner;
        AssetStatus status;
        bool isTransferable;
        uint256 bundleId;
    }

    struct AssetBundle {
        uint256 bundleId;
        uint256[] assetIds;
        string name;
        string description;
        uint256 totalValue;
        address owner;
    }

    struct Auction {
        uint256 auctionId;
        uint256 assetId;
        address seller;
        uint256 startingPrice;
        uint256 currentBid;
        address currentBidder;
        uint256 endTime;
        bool isActive;
    }

    struct Rental {
        uint256 rentalId;
        uint256 assetId;
        address owner;
        address renter;
        uint256 startTime;
        uint256 endTime;
        uint256 price;
        bool isActive;
    }

    mapping(uint256 => Asset) private _assets;
    mapping(address => uint256[]) private _userAssets;
    mapping(uint256 => AssetBundle) private _assetBundles;
    mapping(uint256 => Auction) private _auctions;
    mapping(uint256 => Rental) private _rentals;

    // Events
    event AssetCreated(uint256 indexed assetId, address indexed owner, string name, uint256 value);
    event AssetTransferred(uint256 indexed assetId, address indexed from, address indexed to);
    event AssetBundleCreated(uint256 indexed bundleId, address indexed owner, uint256[] assetIds);
    event AuctionCreated(uint256 indexed auctionId, uint256 indexed assetId, uint256 startingPrice);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionSettled(uint256 indexed auctionId, address indexed winner, uint256 amount);
    event RentalCreated(uint256 indexed rentalId, uint256 indexed assetId, address renter);
    event RentalPaid(uint256 indexed rentalId, uint256 amount);

    // Modifiers
    modifier onlyAssetOwner(uint256 assetId) {
        require(_assets[assetId].owner == msg.sender, "Not asset owner");
        _;
    }

    modifier assetExists(uint256 assetId) {
        require(_assets[assetId].id != 0, "Asset does not exist");
        _;
    }

    modifier notLocked(uint256 assetId) {
        require(_assets[assetId].status != AssetStatus.Locked, "Asset is locked");
        _;
    }

    // Core Functions
    function createAsset(string memory name, uint256 value) public returns (uint256) {
        _assetIds.increment();
        uint256 newAssetId = _assetIds.current();

        _assets[newAssetId] = Asset({
            id: newAssetId,
            name: name,
            value: value,
            owner: msg.sender,
            status: AssetStatus.Active,
            isTransferable: true,
            bundleId: 0
        });

        _userAssets[msg.sender].push(newAssetId);
        emit AssetCreated(newAssetId, msg.sender, name, value);
        return newAssetId;
    }

    function transferAsset(uint256 assetId, address to) public onlyAssetOwner(assetId) notLocked(assetId) {
        require(_assets[assetId].isTransferable, "Asset is not transferable");

        _removeAssetFromUser(msg.sender, assetId);
        _assets[assetId].owner = to;
        _userAssets[to].push(assetId);

        emit AssetTransferred(assetId, msg.sender, to);
    }

    function createBundle(uint256[] memory assetIds, string memory name, string memory description) public returns (uint256) {
        require(assetIds.length > 0, "Empty bundle not allowed");

        _bundleIds.increment();
        uint256 newBundleId = _bundleIds.current();
        uint256 totalValue = 0;

        for (uint256 i = 0; i < assetIds.length; i++) {
            uint256 assetId = assetIds[i];
            require(_assets[assetId].owner == msg.sender, "Not owner of all assets");
            require(_assets[assetId].status == AssetStatus.Active, "Asset not active");

            _assets[assetId].bundleId = newBundleId;
            totalValue = totalValue.add(_assets[assetId].value);
        }

        _assetBundles[newBundleId] = AssetBundle({
            bundleId: newBundleId,
            assetIds: assetIds,
            name: name,
            description: description,
            totalValue: totalValue,
            owner: msg.sender
        });

        emit AssetBundleCreated(newBundleId, msg.sender, assetIds);
        return newBundleId;
    }

    function createAuction(uint256 assetId, uint256 startingPrice, uint256 duration) 
        public 
        onlyAssetOwner(assetId) 
        notLocked(assetId) 
        returns (uint256) 
    {
        require(_assets[assetId].status == AssetStatus.Active, "Asset not active");

        _auctionIds.increment();
        uint256 newAuctionId = _auctionIds.current();

        _auctions[newAuctionId] = Auction({
            auctionId: newAuctionId,
            assetId: assetId,
            seller: msg.sender,
            startingPrice: startingPrice,
            currentBid: 0,
            currentBidder: address(0),
            endTime: block.timestamp + duration,
            isActive: true
        });

        _assets[assetId].status = AssetStatus.InAuction;
        emit AuctionCreated(newAuctionId, assetId, startingPrice);
        return newAuctionId;
    }

    function placeBid(uint256 auctionId) public payable {
        Auction storage auction = _auctions[auctionId];
        require(auction.isActive, "Auction not active");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(msg.value > auction.currentBid, "Bid too low");

        if (auction.currentBidder != address(0)) {
            payable(auction.currentBidder).transfer(auction.currentBid);
        }

        auction.currentBid = msg.value;
        auction.currentBidder = msg.sender;

        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    function settleAuction(uint256 auctionId) public {
        Auction storage auction = _auctions[auctionId];
        require(auction.isActive, "Auction not active");
        require(block.timestamp >= auction.endTime, "Auction still active");

        auction.isActive = false;

        if (auction.currentBidder != address(0)) {
            _assets[auction.assetId].owner = auction.currentBidder;
            payable(auction.seller).transfer(auction.currentBid);
        }

        _assets[auction.assetId].status = AssetStatus.Active;
        emit AuctionSettled(auctionId, auction.currentBidder, auction.currentBid);
    }

    function createRental(uint256 assetId, uint256 duration, uint256 price) 
        public 
        onlyAssetOwner(assetId) 
        notLocked(assetId) 
        returns (uint256) 
    {
        require(_assets[assetId].status == AssetStatus.Active, "Asset not active");

        _rentalIds.increment();
        uint256 newRentalId = _rentalIds.current();

        _rentals[newRentalId] = Rental({
            rentalId: newRentalId,
            assetId: assetId,
            owner: msg.sender,
            renter: address(0),
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            price: price,
            isActive: true
        });

        _assets[assetId].status = AssetStatus.Rented;
        emit RentalCreated(newRentalId, assetId, address(0));
        return newRentalId;
    }

    function payRent(uint256 rentalId) public payable {
        Rental storage rental = _rentals[rentalId];
        require(rental.isActive, "Rental not active");
        require(msg.value == rental.price, "Incorrect payment");

        rental.renter = msg.sender;
        payable(rental.owner).transfer(msg.value);

        emit RentalPaid(rentalId, msg.value);
    }

    // Internal Helper Functions
    function _removeAssetFromUser(address user, uint256 assetId) internal {
        uint256[] storage userAssets = _userAssets[user];
        for (uint256 i = 0; i < userAssets.length; i++) {
            if (userAssets[i] == assetId) {
                userAssets[i] = userAssets[userAssets.length - 1];
                userAssets.pop();
                break;
            }
        }
    }
}
