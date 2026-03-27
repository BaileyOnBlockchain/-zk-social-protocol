// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";

/**
 * @title GroupManager
 * @notice Manages private groups with Semaphore integration
 * @dev Creates Semaphore groups and stores group metadata
 */
contract GroupManager is Ownable, ReentrancyGuard {
    ISemaphore public immutable semaphore;
    
    // Group structure
    struct Group {
        uint256 semaphoreGroupId;
        address creator;
        string name;
        string description;
        bool encrypted;
        bool zkAccess;
        uint256 createdAt;
        uint256 memberCount;
    }
    
    // Mapping: groupId => Group
    mapping(uint256 => Group) public groups;
    
    // Mapping: creator => groupIds[]
    mapping(address => uint256[]) public userGroups;
    
    // Counter for group IDs
    uint256 public groupCounter;
    
    // Events
    event GroupCreated(
        uint256 indexed groupId,
        uint256 indexed semaphoreGroupId,
        address indexed creator,
        string name,
        bool encrypted,
        bool zkAccess
    );
    
    event MemberAdded(
        uint256 indexed groupId,
        uint256 indexed identityCommitment
    );
    
    constructor(address _semaphore) Ownable(msg.sender) {
        semaphore = ISemaphore(_semaphore);
    }
    
    /**
     * @notice Create a new private group
     * @param name Group name
     * @param description Group description
     * @param encrypted Whether messages are encrypted
     * @param zkAccess Whether group requires ZK-proof access
     * @return groupId The new group ID
     */
    function createGroup(
        string calldata name,
        string calldata description,
        bool encrypted,
        bool zkAccess
    ) external nonReentrant returns (uint256 groupId) {
        require(bytes(name).length > 0, "GroupManager: Name required");
        require(bytes(name).length <= 100, "GroupManager: Name too long");
        require(bytes(description).length <= 500, "GroupManager: Description too long");
        
        // Create Semaphore group
        uint256 semaphoreGroupId = semaphore.createGroup(msg.sender);
        
        // Create group record
        groupId = groupCounter++;
        groups[groupId] = Group({
            semaphoreGroupId: semaphoreGroupId,
            creator: msg.sender,
            name: name,
            description: description,
            encrypted: encrypted,
            zkAccess: zkAccess,
            createdAt: block.timestamp,
            memberCount: 0
        });
        
        // Track user's groups
        userGroups[msg.sender].push(groupId);
        
        emit GroupCreated(groupId, semaphoreGroupId, msg.sender, name, encrypted, zkAccess);
    }
    
    /**
     * @notice Join a group (add member to Semaphore group)
     * @param groupId The group ID
     * @param identityCommitment User's Semaphore identity commitment
     */
    function joinGroup(uint256 groupId, uint256 identityCommitment) external {
        Group storage group = groups[groupId];
        require(group.creator != address(0), "GroupManager: Group does not exist");
        
        // Add to Semaphore group
        semaphore.addMember(group.semaphoreGroupId, identityCommitment);
        
        group.memberCount++;
        emit MemberAdded(groupId, identityCommitment);
    }
    
    /**
     * @notice Get group details
     */
    function getGroup(uint256 groupId) external view returns (Group memory) {
        return groups[groupId];
    }
    
    /**
     * @notice Get user's created groups
     */
    function getUserGroups(address user) external view returns (uint256[] memory) {
        return userGroups[user];
    }
    
    /**
     * @notice Get total number of groups
     */
    function getTotalGroups() external view returns (uint256) {
        return groupCounter;
    }
}

