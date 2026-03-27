// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PrivNet
 * @notice Main contract for anonymous posting on PrivNet using Semaphore
 * @dev Posts are anonymous but verifiable via ZK-proofs
 */
contract PrivNet is Ownable, ReentrancyGuard {
    // Semaphore interface for proof verification
    ISemaphore public semaphore;
    
    // PrivNet Semaphore Group ID
    uint256 public constant PRIVNET_GROUP_ID = 1;
    
    // Post structure
    struct Post {
        bytes32 contentHash;
        uint256 timestamp;
        bytes32 nullifierHash;
        bool verified;
        uint256 totalTips;
        address verifiableAuthor; // Optional: only set if user opts into verifiable mode
    }
    
    // Mapping: postId => Post
    mapping(bytes32 => Post) public posts;
    
    // Mapping: nullifierHash => used (prevents double-posting)
    mapping(bytes32 => bool) public usedNullifiers;
    
    // Mapping: user address => total earned
    mapping(address => uint256) public userEarnings;
    
    // Events
    event PostCreated(
        bytes32 indexed postId,
        bytes32 contentHash,
        bytes32 nullifierHash,
        uint256 timestamp,
        address indexed verifiableAuthor
    );
    
    event PostTipped(
        bytes32 indexed postId,
        address indexed tipper,
        uint256 amount,
        address indexed recipient
    );
    
    event UserJoinedGroup(uint256 indexed identityCommitment);
    
    constructor(address _semaphore) Ownable(msg.sender) {
        semaphore = ISemaphore(_semaphore);
    }
    
    /**
     * @notice Join the PrivNet Semaphore group
     * @param identityCommitment User's Semaphore identity commitment
     */
    function joinGroup(uint256 identityCommitment) external {
        semaphore.addMember(PRIVNET_GROUP_ID, identityCommitment);
        emit UserJoinedGroup(identityCommitment);
    }
    
    /**
     * @notice Create an anonymous post with Semaphore proof
     * @param postId Unique identifier for the post (hash of content + timestamp)
     * @param contentHash Hash of the post content
     * @param nullifierHash Semaphore nullifier hash
     * @param proof Semaphore proof bytes
     * @param verifiableAuthor Optional: user's address if opting into verifiable mode (0x0 for anonymous)
     */
    function createPost(
        bytes32 postId,
        bytes32 contentHash,
        bytes32 nullifierHash,
        bytes calldata proof,
        address verifiableAuthor
    ) external nonReentrant {
        // Prevent double-posting with same nullifier
        require(!usedNullifiers[nullifierHash], "PrivNet: Nullifier already used");
        
        // Verify Semaphore proof
        // Note: In production, this would verify the proof bytes against the Semaphore verifier
        // For now, we validate the nullifier is unique
        usedNullifiers[nullifierHash] = true;
        
        // Prevent duplicate post IDs
        require(posts[postId].timestamp == 0, "PrivNet: Post ID already exists");
        
        // Create post
        posts[postId] = Post({
            contentHash: contentHash,
            timestamp: block.timestamp,
            nullifierHash: nullifierHash,
            verified: true,
            totalTips: 0,
            verifiableAuthor: verifiableAuthor
        });
        
        emit PostCreated(postId, contentHash, nullifierHash, block.timestamp, verifiableAuthor);
    }
    
    /**
     * @notice Tip a post (anonymous or verifiable)
     * @param postId The post to tip
     * @param recipient If post is verifiable, tip goes to author; otherwise to contract
     */
    function tipPost(bytes32 postId, address recipient) external payable nonReentrant {
        require(msg.value > 0, "PrivNet: Tip must be greater than 0");
        require(posts[postId].timestamp > 0, "PrivNet: Post does not exist");
        require(posts[postId].verified, "PrivNet: Post not verified");
        
        Post storage post = posts[postId];
        post.totalTips += msg.value;
        
        // If verifiable post, send to author; otherwise keep in contract for distribution
        if (post.verifiableAuthor != address(0)) {
            userEarnings[post.verifiableAuthor] += msg.value;
            (bool success, ) = post.verifiableAuthor.call{value: msg.value}("");
            require(success, "PrivNet: Transfer failed");
        } else {
            // Anonymous posts: accumulate in contract for later distribution
            // Could implement a staking pool or DAO treasury
        }
        
        emit PostTipped(postId, msg.sender, msg.value, recipient);
    }
    
    /**
     * @notice Get post details
     */
    function getPost(bytes32 postId) external view returns (Post memory) {
        return posts[postId];
    }
    
    /**
     * @notice Get user's total earnings
     */
    function getEarnings(address user) external view returns (uint256) {
        return userEarnings[user];
    }
}

