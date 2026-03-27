// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TokenGatedChannel
 * @notice Token-gated access control for VIP channels
 * @dev Users must hold minimum token balance or NFT to access
 */
contract TokenGatedChannel is Ownable, ReentrancyGuard {
    constructor() Ownable(msg.sender) {}
    // Channel structure
    struct Channel {
        string name;
        address tokenAddress; // ERC20 or ERC721 address (0x0 for no gating)
        bool isNFT; // true if ERC721, false if ERC20
        uint256 minBalance; // Minimum token balance or NFT token ID
        bool active;
        mapping(address => bool) whitelist; // Optional whitelist
        bool useWhitelist;
    }
    
    mapping(uint256 => Channel) public channels;
    mapping(uint256 => mapping(address => bool)) public accessGranted; // channelId => user => hasAccess
    uint256 public channelCount;
    
    // Events
    event ChannelCreated(
        uint256 indexed channelId,
        string name,
        address tokenAddress,
        bool isNFT,
        uint256 minBalance
    );
    event AccessGranted(uint256 indexed channelId, address indexed user);
    event AccessRevoked(uint256 indexed channelId, address indexed user);
    event ChannelUpdated(uint256 indexed channelId);
    
    /**
     * @notice Create a token-gated channel
     */
    function createChannel(
        string memory name,
        address tokenAddress,
        bool isNFT,
        uint256 minBalance,
        bool useWhitelist
    ) external onlyOwner returns (uint256) {
        uint256 channelId = channelCount++;
        Channel storage channel = channels[channelId];
        channel.name = name;
        channel.tokenAddress = tokenAddress;
        channel.isNFT = isNFT;
        channel.minBalance = minBalance;
        channel.active = true;
        channel.useWhitelist = useWhitelist;
        
        emit ChannelCreated(channelId, name, tokenAddress, isNFT, minBalance);
        return channelId;
    }
    
    /**
     * @notice Check if user has access to channel
     */
    function hasAccess(uint256 channelId, address user) public view returns (bool) {
        Channel storage channel = channels[channelId];
        require(channel.active, "TokenGatedChannel: Channel inactive");
        
        // Check whitelist if enabled
        if (channel.useWhitelist) {
            return channel.whitelist[user];
        }
        
        // Check token gating
        if (channel.tokenAddress == address(0)) {
            return true; // No gating
        }
        
        if (channel.isNFT) {
            // ERC721: check if user owns the NFT
            IERC721 nft = IERC721(channel.tokenAddress);
            return nft.ownerOf(channel.minBalance) == user;
        } else {
            // ERC20: check if user has minimum balance
            IERC20 token = IERC20(channel.tokenAddress);
            return token.balanceOf(user) >= channel.minBalance;
        }
    }
    
    /**
     * @notice Request access to channel (grants if requirements met)
     */
    function requestAccess(uint256 channelId) external nonReentrant {
        require(hasAccess(channelId, msg.sender), "TokenGatedChannel: Access denied");
        accessGranted[channelId][msg.sender] = true;
        emit AccessGranted(channelId, msg.sender);
    }
    
    /**
     * @notice Revoke access (owner only)
     */
    function revokeAccess(uint256 channelId, address user) external onlyOwner {
        accessGranted[channelId][user] = false;
        emit AccessRevoked(channelId, user);
    }
    
    /**
     * @notice Add user to whitelist
     */
    function addToWhitelist(uint256 channelId, address user) external onlyOwner {
        channels[channelId].whitelist[user] = true;
    }
    
    /**
     * @notice Remove user from whitelist
     */
    function removeFromWhitelist(uint256 channelId, address user) external onlyOwner {
        channels[channelId].whitelist[user] = false;
    }
    
    /**
     * @notice Toggle channel active status
     */
    function setChannelActive(uint256 channelId, bool active) external onlyOwner {
        channels[channelId].active = active;
        emit ChannelUpdated(channelId);
    }
    
    /**
     * @notice Get channel info
     */
    function getChannel(uint256 channelId)
        external
        view
        returns (
            string memory name,
            address tokenAddress,
            bool isNFT,
            uint256 minBalance,
            bool active,
            bool useWhitelist
        )
    {
        Channel storage channel = channels[channelId];
        return (
            channel.name,
            channel.tokenAddress,
            channel.isNFT,
            channel.minBalance,
            channel.active,
            channel.useWhitelist
        );
    }
}

