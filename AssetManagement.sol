// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Roles.sol";

contract AssetManagement is ReentrancyGuard, Roles {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private _assetIds;
    Counters.Counter private _bundleIds;
    Counters.Counter private _auctionIds;
    Counters.Counter private _rentalIds;

    struct Asset {
        uint256 id;
        string name;
        uint256 value;
        bool isTokenized;
        uint256 tokenizedAmount;
        uint256 unlockTime;
        bool isTransferable;
        address owner;
        AssetMetadata metadata;
        AssetStatus status;
        uint256[] linkedAssets;
        bool isBundle;
        uint256 bundleId;
        uint256 rentId;
        uint256 auctionId;
    }

    struct AssetMetadata {
        string description;
        string imageUri;
        string documentUri;
        mapping(string => string) attributes;
        uint256 creationDate;
        uint256 lastUpdated;
        string category;
        string[] tags;
    }

    struct AssetBundle {
        uint256 bundleId;
        uint256[] assetIds;
        string name;
        string description;
        uint256 totalValue;
        address owner;
        bool isLocked;
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
        bool isSettled;
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
        bool isPaid;
    }

    enum AssetStatus {
        Active,
        Locked,
        InAuction,
        Rented,
        Burned,
        Suspended
    }

    // Main storage
    mapping(uint256 => Asset) private _assets;
    mapping(address => uint256[]) private _userAssets;
    mapping(uint256 => AssetBundle) private _assetBundles;
    mapping(uint256 => Auction) private _auctions;
    mapping(uint256 => Rental) private _rentals;
    mapping(address => mapping(uint256 => uint256)) private _assetCollateral;

    // Events
    event AssetCreated(uint256 indexed assetId, address indexed owner, string name, uint256 value);
    event AssetUpdated(uint256 indexed assetId, string name, uint256 value);
    event AssetTransferred(uint256 indexed assetId, address indexed from, address indexed to);
    event AssetTokenized(uint256 indexed assetId, uint256 amount);
    event AssetBundleCreated(uint256 indexed bundleId, address indexed owner, uint256[] assetIds);
    event AuctionCreated(uint256 indexed auctionId, uint256 indexed assetId, uint256 startingPrice);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionSettled(uint256 indexed auctionId, address indexed winner, uint256 amount);
    event RentalCreated(uint256 indexed rentalId, uint256 indexed assetId, address renter);
    event RentalPaid(uint256 indexed rentalId, uint256 amount);
    event AssetMetadataUpdated(uint256 indexed assetId);
    event AssetLocked(uint256 indexed assetId, uint256 unlockTime);
    event AssetUnlocked(uint256 indexed assetId);
    event AssetBurned(uint256 indexed assetId);

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

    // Asset Management Functions
    function createAsset(
        string memory name,
        uint256 value,
        string memory description,
        string memory imageUri,
        string memory category,
        string[] memory tags
    ) public returns (uint256) {
        _assetIds.increment();
        uint256 newAssetId = _assetIds.current();

        Asset storage asset = _assets[newAssetId];
        asset.id = newAssetId;
        asset.name = name;
        asset.value = value;
        asset.owner = msg.sender;
        asset.status = AssetStatus.Active;
        asset.isTransferable = true;

        // Set metadata
        asset.metadata.description = description;
        asset.metadata.imageUri = imageUri;
        asset.metadata.category = category;
        asset.metadata.tags = tags;
        asset.metadata.creationDate = block.timestamp;
        asset.metadata.lastUpdated = block.timestamp;

        _userAssets[msg.sender].push(newAssetId);

        emit AssetCreated(newAssetId, msg.sender, name, value);
        return newAssetId;
    }

    function tokenizeAsset(uint256 assetId, uint256 amount) 
        public 
        onlyAssetOwner(assetId) 
        assetExists(assetId) 
        notLocked(assetId) 
    {
        Asset storage asset = _assets[assetId];
        require(!asset.isTokenized, "Asset already tokenized");
        require(asset.tokenizedAmount.add(amount) <= asset.value, "Amount exceeds asset value");

        asset.tokenizedAmount = asset.tokenizedAmount.add(amount);
        if (asset.tokenizedAmount == asset.value) {
            asset.isTokenized = true;
        }

        emit AssetTokenized(assetId, amount);
    }

    function createAssetBundle(
        uint256[] memory assetIds,
        string memory name,
        string memory description
    ) public returns (uint256) {
        require(assetIds.length > 0, "Empty bundle not allowed");
        
        _bundleIds.increment();
        uint256 newBundleId = _bundleIds.current();
        uint256 totalValue = 0;

        // Verify ownership and calculate total value
        for (uint256 i = 0; i < assetIds.length; i++) {
            require(_assets[assetIds[i]].owner == msg.sender, "Not owner of all assets");
            require(_assets[assetIds[i]].status == AssetStatus.Active, "Asset not available");
            totalValue = totalValue.add(_assets[assetIds[i]].value);
            
            _assets[assetIds[i]].bundleId = newBundleId;
            _assets[assetIds[i]].isBundle = true;
        }

        AssetBundle storage bundle = _assetBundles[newBundleId];
        bundle.bundleId = newBundleId;
        bundle.assetIds = assetIds;
        bundle.name = name;
        bundle.description = description;
        bundle.totalValue = totalValue;
        bundle.owner = msg.sender;

        emit AssetBundleCreated(newBundleId, msg.sender, assetIds);
        return newBundleId;
    }

    function createAuction(
        uint256 assetId,
        uint256 startingPrice,
        uint256 duration
    ) public onlyAssetOwner(assetId) notLocked(assetId) returns (uint256) {
        require(_assets[assetId].status == AssetStatus.Active, "Asset not available for auction");
        
        _auctionIds.increment();
        uint256 newAuctionId = _auctionIds.current();

        Auction storage auction = _auctions[newAuctionId];
        auction.auctionId = newAuctionId;
        auction.assetId = assetId;
        auction.seller = msg.sender;
        auction.startingPrice = startingPrice;
        auction.endTime = block.timestamp + duration;
        auction.isActive = true;

        _assets[assetId].status = AssetStatus.InAuction;
        _assets[assetId].auctionId = newAuctionId;

        emit AuctionCreated(newAuctionId, assetId, startingPrice);
        return newAuctionId;
    }

    function placeBid(uint256 auctionId) public payable nonReentrant {
        Auction storage auction = _auctions[auctionId];
        require(auction.isActive, "Auction not active");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(msg.value > auction.currentBid, "Bid too low");

        if (auction.currentBidder != address(0)) {
            // Refund the previous bidder
            payable(auction.currentBidder).transfer(auction.currentBid);
        }

        auction.currentBid = msg.value;
        auction.currentBidder = msg.sender;

        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    function settleAuction(uint256 auctionId) public nonReentrant {
        Auction storage auction = _auctions[auctionId];
        require(auction.isActive, "Auction not active");
        require(block.timestamp >= auction.endTime, "Auction still active");

        auction.isActive = false;
        auction.isSettled = true;

        if (auction.currentBidder != address(0)) {
            // Transfer asset to winner
            Asset storage asset = _assets[auction.assetId];
            _transferAsset(asset.owner, auction.currentBidder, auction.assetId);
            
            // Transfer funds to seller
            payable(auction.seller).transfer(auction.currentBid);
        }

        _assets[auction.assetId].status = AssetStatus.Active;
        _assets[auction.assetId].auctionId = 0;

        emit AuctionSettled(auctionId, auction.currentBidder, auction.currentBid);
    }

    function createRental(
        uint256 assetId,
        uint256 duration,
        uint256 price
    ) public onlyAssetOwner(assetId) notLocked(assetId) returns (uint256) {
        require(_assets[assetId].status == AssetStatus.Active, "Asset not available for rental");
        
        _rentalIds.increment();
        uint256 newRentalId = _rentalIds.current();

        Rental storage rental = _rentals[newRentalId];
        rental.rentalId = newRentalId;
        rental.assetId = assetId;
        rental.owner = msg.sender;
        rental.startTime = block.timestamp;
        rental.endTime = block.timestamp + duration;
        rental.price = price;
        rental.isActive = true;

        _assets[assetId].status = AssetStatus.Rented;
        _assets[assetId].rentId = newRentalId;

        emit RentalCreated(newRentalId, assetId, msg.sender);
        return newRentalId;
    }

    function payRent(uint256 rentalId) public payable nonReentrant {
        Rental storage rental = _rentals[rentalId];
        require(rental.isActive, "Rental not active");
        require(!rental.isPaid, "Rent already paid");
        require(msg.value == rental.price, "Incorrect payment amount");

        rental.isPaid = true;
        rental.renter = msg.sender;

        // Transfer rent to owner
        payable(rental.owner).transfer(msg.value);

        emit RentalPaid(rentalId, msg.value);
    }

    function updateAssetMetadata(
        uint256 assetId,
        string memory description,
        string memory imageUri,
        string memory documentUri,
        string memory category,
        string[] memory tags
    ) public onlyAssetOwner(assetId) {
        Asset storage asset = _assets[assetId];
        asset.metadata.description = description;
        asset.metadata.imageUri = imageUri;
        asset.metadata.documentUri = documentUri;
        asset.metadata.category = category;
        asset.metadata.tags = tags;
        asset.metadata.lastUpdated = block.timestamp;

        emit AssetMetadataUpdated(assetId);
    }

    function lockAsset(uint256 assetId, uint256 duration) 
        public 
        onlyAssetOwner(assetId) 
        notLocked(assetId) 
    {
        Asset storage asset = _assets[assetId];
        asset.status = AssetStatus.Locked;
        asset.unlockTime = block.timestamp + duration;

        emit AssetLocked(assetId, asset.unlockTime);
    }

    function unlockAsset(uint256 assetId) public onlyAssetOwner(assetId) {
        Asset storage asset = _assets[assetId];
        require(asset.status == AssetStatus.Locked, "Asset not locked");
        require(block.timestamp >= asset.unlockTime, "Asset still locked");

        asset.status = AssetStatus.Active;
        asset.unlockTime = 0;

        emit AssetUnlocked(assetId);
    }

    function burnAsset(uint256 assetId) public onlyAssetOwner(assetId) {
        Asset storage asset = _assets[assetId];
        require(asset.status == AssetStatus.Active, "Asset not active");
        
        asset.status = AssetStatus.Burned;
        emit AssetBurned(assetId);
    }

    // View Functions
    function getAsset(uint256 assetId) public view returns (
        uint256 id,
        string memory name,
        uint256 value,
        bool isTokenized,
        uint256 tokenizedAmount,
        address owner,
        AssetStatus status
    ) {
        Asset storage asset = _assets[assetId];
        return (
            asset.id,
            asset.name,
            asset.value,
            asset.isTokenized,
            asset.tokenizedAmount,
            asset.owner,
            asset.status
        );
    }

    function getAssetMetadata(uint256 assetId) public view returns (
        string memory description,
        string memory imageUri,
        string memory documentUri,
        string memory category,
        string[] memory tags,
        uint256 creationDate,
        uint256 lastUpdate
            ) {
        AssetMetadata storage metadata = _assets[assetId].metadata;
        return (
            metadata.description,
            metadata.imageUri,
            metadata.documentUri,
            metadata.category,
            metadata.tags,
            metadata.creationDate,
            metadata.lastUpdated
        );
    }

    function getUserAssets(address user) public view returns (uint256[] memory) {
        return _userAssets[user];
    }

    function getAssetBundle(uint256 bundleId) public view returns (
        uint256 id,
        uint256[] memory assetIds,
        string memory name,
        string memory description,
        uint256 totalValue,
        address owner,
        bool isLocked
    ) {
        AssetBundle storage bundle = _assetBundles[bundleId];
        return (
            bundle.bundleId,
            bundle.assetIds,
            bundle.name,
            bundle.description,
            bundle.totalValue,
            bundle.owner,
            bundle.isLocked
        );
    }

    function getAuction(uint256 auctionId) public view returns (
        uint256 id,
        uint256 assetId,
        address seller,
        uint256 startingPrice,
        uint256 currentBid,
        address currentBidder,
        uint256 endTime,
        bool isActive,
        bool isSettled
    ) {
        Auction storage auction = _auctions[auctionId];
        return (
            auction.auctionId,
            auction.assetId,
            auction.seller,
            auction.startingPrice,
            auction.currentBid,
            auction.currentBidder,
            auction.endTime,
            auction.isActive,
            auction.isSettled
        );
    }

    function getRental(uint256 rentalId) public view returns (
        uint256 id,
        uint256 assetId,
        address owner,
        address renter,
        uint256 startTime,
        uint256 endTime,
        uint256 price,
        bool isActive,
        bool isPaid
    ) {
        Rental storage rental = _rentals[rentalId];
        return (
            rental.rentalId,
            rental.assetId,
            rental.owner,
            rental.renter,
            rental.startTime,
            rental.endTime,
            rental.price,
            rental.isActive,
            rental.isPaid
        );
    }

    // Internal helper functions
    function _transferAsset(address from, address to, uint256 assetId) internal {
        require(_assets[assetId].owner == from, "Not the asset owner");
        require(_assets[assetId].isTransferable, "Asset is not transferable");
        require(_assets[assetId].status == AssetStatus.Active, "Asset is not active");

        // Remove asset from previous owner
        _removeAssetFromUser(from, assetId);

        // Add asset to new owner
        _assets[assetId].owner = to;
        _userAssets[to].push(assetId);

        emit AssetTransferred(assetId, from, to);
    }

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

    // Asset collateralization functions
    function collateralizeAsset(uint256 assetId, uint256 amount) public onlyAssetOwner(assetId) {
        require(_assets[assetId].status == AssetStatus.Active, "Asset not active");
        require(amount <= _assets[assetId].value, "Collateral exceeds asset value");

        _assetCollateral[msg.sender][assetId] = amount;
        _assets[assetId].status = AssetStatus.Locked;

        emit AssetCollateralized(msg.sender, assetId, amount);
    }

    function releaseCollateral(uint256 assetId) public onlyAssetOwner(assetId) {
        require(_assets[assetId].status == AssetStatus.Locked, "Asset not locked");
        require(_assetCollateral[msg.sender][assetId] > 0, "No collateral to release");

        _assetCollateral[msg.sender][assetId] = 0;
        _assets[assetId].status = AssetStatus.Active;

        emit AssetCollateralized(msg.sender, assetId, 0);
    }

    // Asset fractionalization
    function fractionalizeAsset(uint256 assetId, uint256 fractions) public onlyAssetOwner(assetId) {
        require(_assets[assetId].status == AssetStatus.Active, "Asset not active");
        require(!_assets[assetId].isTokenized, "Asset already tokenized");

        _assets[assetId].isTokenized = true;
        _assets[assetId].tokenizedAmount = fractions;

        // Note: Actual token minting should be handled in the main contract
        emit AssetFractionalized(msg.sender, assetId, fractions);
    }

    // Asset bundling and unbundling
    function createBundle(uint256[] memory assetIds, string memory name, string memory description) public {
        require(assetIds.length > 0, "Bundle must contain at least one asset");

        _bundleIds.increment();
        uint256 newBundleId = _bundleIds.current();

        AssetBundle storage newBundle = _assetBundles[newBundleId];
        newBundle.bundleId = newBundleId;
        newBundle.assetIds = assetIds;
        newBundle.name = name;
        newBundle.description = description;
        newBundle.owner = msg.sender;

        uint256 totalValue = 0;
        for (uint256 i = 0; i < assetIds.length; i++) {
            require(_assets[assetIds[i]].owner == msg.sender, "Must own all assets in bundle");
            require(_assets[assetIds[i]].status == AssetStatus.Active, "All assets must be active");
            
            _assets[assetIds[i]].bundleId = newBundleId;
            _assets[assetIds[i]].status = AssetStatus.Locked;
            totalValue += _assets[assetIds[i]].value;
        }

        newBundle.totalValue = totalValue;

        emit AssetBundleCreated(newBundleId, msg.sender, assetIds);
    }

    function unbundleAssets(uint256 bundleId) public {
        AssetBundle storage bundle = _assetBundles[bundleId];
        require(bundle.owner == msg.sender, "Not the bundle owner");
        require(!bundle.isLocked, "Bundle is locked");

        for (uint256 i = 0; i < bundle.assetIds.length; i++) {
            uint256 assetId = bundle.assetIds[i];
            _assets[assetId].bundleId = 0;
            _assets[assetId].status = AssetStatus.Active;
        }

        delete _assetBundles[bundleId];

        emit AssetBundleUnbundled(bundleId, msg.sender);
    }

    // Events not previously defined
    event AssetCollateralized(address indexed owner, uint256 indexed assetId, uint256 amount);
    event AssetFractionalized(address indexed owner, uint256 indexed assetId, uint256 fractions);
    event AssetBundleUnbundled(uint256 indexed bundleId, address indexed owner);

    // Function to update asset value
    function updateAssetValue(uint256 assetId, uint256 newValue) public onlyAssetOwner(assetId) {
        _assets[assetId].value = newValue;
        emit AssetValueUpdated(assetId, newValue);
    }

    // Function to set asset transferability
    function setAssetTransferability(uint256 assetId, bool isTransferable) public onlyAssetOwner(assetId) {
        _assets[assetId].isTransferable = isTransferable;
        emit AssetTransferabilitySet(assetId, isTransferable);
    }

    // Additional events
    event AssetTransferabilitySet(uint256 indexed assetId, bool isTransferable);

    // Function to get total value of user's assets
    function getUserTotalAssetValue(address user) public view returns (uint256) {
        uint256 totalValue = 0;
        uint256[] memory userAssets = _userAssets[user];
        for (uint256 i = 0; i < userAssets.length; i++) {
            totalValue += _assets[userAssets[i]].value;
        }
        return totalValue;
    }

    // Function to get all active auctions
    function getActiveAuctions() public view returns (uint256[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= _auctionIds.current(); i++) {
            if (_auctions[i].isActive) {
                activeCount++;
            }
        }

        uint256[] memory activeAuctions = new uint256[](activeCount);
        uint256 index = 0;
        for (uint256 i = 1; i <= _auctionIds.current(); i++) {
            if (_auctions[i].isActive) {
                activeAuctions[index] = i;
                index++;
            }
        }

        return activeAuctions;
    }

    // Function to get all active rentals
    function getActiveRentals() public view returns (uint256[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= _rentalIds.current(); i++) {
            if (_rentals[i].isActive) {
                activeCount++;
            }
        }

        uint256[] memory activeRentals = new uint256[](activeCount);
        uint256 index = 0;
        for (uint256 i = 1; i <= _rentalIds.current(); i++) {
            if (_rentals[i].isActive) {
                activeRentals[index] = i;
                index++;
            }
        }

        return activeRentals;
    }

    // Function to extend rental period
    function extendRental(uint256 rentalId, uint256 additionalDuration) public payable {
        Rental storage rental = _rentals[rentalId];
        require(rental.isActive, "Rental not active");
        require(msg.sender == rental.renter, "Not the renter");
        
        uint256 additionalCost = (rental.price * additionalDuration) / (rental.endTime - rental.startTime);
        require(msg.value >= additionalCost, "Insufficient payment for extension");

        rental.endTime += additionalDuration;
        
        // Transfer additional rent to owner
        payable(rental.owner).transfer(additionalCost);

        // Refund excess payment if any
        if (msg.value > additionalCost) {
            payable(msg.sender).transfer(msg.value - additionalCost);
        }

        emit RentalExtended(rentalId, additionalDuration, additionalCost);
    }

    // Event for rental extension
    event RentalExtended(uint256 indexed rentalId, uint256 additionalDuration, uint256 additionalCost);

    // Function to cancel auction (only by seller and if no bids placed)
    function cancelAuction(uint256 auctionId) public {
        Auction storage auction = _auctions[auctionId];
        require(msg.sender == auction.seller, "Not the seller");
        require(auction.isActive, "Auction not active");
        require(auction.currentBidder == address(0), "Bids already placed");

        auction.isActive = false;
        _assets[auction.assetId].status = AssetStatus.Active;
        _assets[auction.assetId].auctionId = 0;

        emit AuctionCancelled(auctionId);
    }

    // Event for auction cancellation
    event AuctionCancelled(uint256 indexed auctionId);

    // Function to get asset history (transfers, auctions, rentals)
    function getAssetHistory(uint256 assetId) public view returns (
        address[] memory previousOwners,
        uint256[] memory auctionIds,
        uint256[] memory rentalIds
    ) {
        // Note: This is a simplified version. In a real-world scenario, 
        // you might want to implement a more sophisticated event logging system.
        return (_assetHistory[assetId].previousOwners, _assetHistory[assetId].auctionIds, _assetHistory[assetId].rentalIds);
    }

    // Struct to store asset history
    struct AssetHistory {
        address[] previousOwners;
        uint256[] auctionIds;
        uint256[] rentalIds;
    }

    mapping(uint256 => AssetHistory) private _assetHistory;

}