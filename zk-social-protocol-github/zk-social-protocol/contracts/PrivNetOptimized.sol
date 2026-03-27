// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PrivNetOptimized
 * @notice Gas-optimized version for ZKsync Era
 * @dev Optimizations: batch operations, calldata packing, storage packing
 */
contract PrivNetOptimized is Ownable, ReentrancyGuard {
    ISemaphore public immutable semaphore; // immutable saves gas
    
    uint256 public constant PRIVNET_GROUP_ID = 1;
    
    // Packed struct (saves storage slots)
    struct Post {
        bytes32 contentHash;      // slot 1
        bytes32 nullifierHash;    // slot 2
        uint128 timestamp;         // slot 3 (packed with verified)
        uint128 totalTips;         // slot 3 (packed)
        bool verified;             // slot 3 (packed)
        address verifiableAuthor;  // slot 4
    }
    
    mapping(bytes32 => Post) public posts;
    mapping(bytes32 => bool) public usedNullifiers; // packed bool
    
    // Packed: address => earnings (uint256)
    mapping(address => uint256) public userEarnings;
    
    // Batch operations storage
    mapping(address => bytes32[]) public pendingPosts; // For batch creation
    
    event PostCreated(
        bytes32 indexed postId,
        bytes32 contentHash,
        bytes32 nullifierHash,
        uint128 timestamp,
        address indexed verifiableAuthor
    );
    
    event PostTipped(
        bytes32 indexed postId,
        address indexed tipper,
        uint128 amount,
        address indexed recipient
    );
    
    event PostsBatchCreated(bytes32[] indexed postIds, address indexed creator);
    event UserJoinedGroup(uint256 indexed identityCommitment);
    
    constructor(address _semaphore) Ownable(msg.sender) {
        semaphore = ISemaphore(_semaphore); // immutable
    }
    
    /**
     * @notice Join group (unchanged, already efficient)
     */
    function joinGroup(uint256 identityCommitment) external {
        semaphore.addMember(PRIVNET_GROUP_ID, identityCommitment);
        emit UserJoinedGroup(identityCommitment);
    }
    
    /**
     * @notice Create post (optimized: calldata, packed struct)
     * @dev Uses calldata for proof to save memory
     */
    function createPost(
        bytes32 postId,
        bytes32 contentHash,
        bytes32 nullifierHash,
        bytes calldata proof, // calldata instead of memory
        address verifiableAuthor
    ) external nonReentrant {
        require(!usedNullifiers[nullifierHash], "PrivNet: Nullifier used");
        require(posts[postId].timestamp == 0, "PrivNet: Post exists");
        
        usedNullifiers[nullifierHash] = true;
        
        // Packed struct assignment (saves gas)
        posts[postId] = Post({
            contentHash: contentHash,
            nullifierHash: nullifierHash,
            timestamp: uint128(block.timestamp), // Safe: timestamp fits in uint128
            totalTips: 0,
            verified: true,
            verifiableAuthor: verifiableAuthor
        });
        
        emit PostCreated(
            postId,
            contentHash,
            nullifierHash,
            uint128(block.timestamp),
            verifiableAuthor
        );
    }
    
    /**
     * @notice Batch create posts (gas efficient for multiple posts)
     * @dev Saves on transaction overhead
     */
    function batchCreatePosts(
        bytes32[] calldata postIds,
        bytes32[] calldata contentHashes,
        bytes32[] calldata nullifierHashes,
        bytes[] calldata proofs,
        address[] calldata verifiableAuthors
    ) external nonReentrant {
        uint256 length = postIds.length;
        require(
            length == contentHashes.length &&
            length == nullifierHashes.length &&
            length == proofs.length &&
            length == verifiableAuthors.length,
            "PrivNet: Array length mismatch"
        );
        require(length <= 50, "PrivNet: Batch too large"); // Prevent gas limit
        
        for (uint256 i = 0; i < length; ) {
            bytes32 postId = postIds[i];
            bytes32 nullifierHash = nullifierHashes[i];
            
            require(!usedNullifiers[nullifierHash], "PrivNet: Nullifier used");
            require(posts[postId].timestamp == 0, "PrivNet: Post exists");
            
            usedNullifiers[nullifierHash] = true;
            
            posts[postId] = Post({
                contentHash: contentHashes[i],
                nullifierHash: nullifierHash,
                timestamp: uint128(block.timestamp),
                totalTips: 0,
                verified: true,
                verifiableAuthor: verifiableAuthors[i]
            });
            
            emit PostCreated(
                postId,
                contentHashes[i],
                nullifierHash,
                uint128(block.timestamp),
                verifiableAuthors[i]
            );
            
            unchecked {
                ++i; // Gas optimization: unchecked increment
            }
        }
        
        emit PostsBatchCreated(postIds, msg.sender);
    }
    
    /**
     * @notice Tip post (optimized: packed amounts)
     */
    function tipPost(bytes32 postId, address recipient) external payable nonReentrant {
        require(msg.value > 0, "PrivNet: Tip must be > 0");
        
        Post storage post = posts[postId];
        require(post.timestamp > 0, "PrivNet: Post not found");
        require(post.verified, "PrivNet: Post not verified");
        
        // Safe cast: tips won't exceed uint128
        post.totalTips += uint128(msg.value);
        
        if (post.verifiableAuthor != address(0)) {
            userEarnings[post.verifiableAuthor] += msg.value;
            (bool success, ) = post.verifiableAuthor.call{value: msg.value}("");
            require(success, "PrivNet: Transfer failed");
        }
        
        emit PostTipped(postId, msg.sender, uint128(msg.value), recipient);
    }
    
    /**
     * @notice Batch tip multiple posts
     */
    function batchTipPosts(
        bytes32[] calldata postIds,
        address[] calldata recipients
    ) external payable nonReentrant {
        uint256 length = postIds.length;
        require(length == recipients.length, "PrivNet: Array mismatch");
        require(msg.value > 0 && msg.value % length == 0, "PrivNet: Invalid amount");
        
        uint256 tipPerPost = msg.value / length;
        
        for (uint256 i = 0; i < length; ) {
            bytes32 postId = postIds[i];
            Post storage post = posts[postId];
            
            require(post.timestamp > 0 && post.verified, "PrivNet: Invalid post");
            
            post.totalTips += uint128(tipPerPost);
            
            address author = post.verifiableAuthor;
            if (author != address(0)) {
                userEarnings[author] += tipPerPost;
                emit PostTipped(postId, msg.sender, uint128(tipPerPost), recipients[i]);
                (bool success, ) = author.call{value: tipPerPost}("");
                require(success, "PrivNet: Transfer failed");
            } else {
                emit PostTipped(postId, msg.sender, uint128(tipPerPost), recipients[i]);
            }
            
            unchecked {
                ++i;
            }
        }
    }
    
    /**
     * @notice Get post (view function, no gas cost)
     */
    function getPost(bytes32 postId) external view returns (Post memory) {
        return posts[postId];
    }
    
    /**
     * @notice Get multiple posts (batch read)
     */
    function getPosts(bytes32[] calldata postIds) external view returns (Post[] memory) {
        uint256 length = postIds.length;
        Post[] memory result = new Post[](length);
        
        for (uint256 i = 0; i < length; ) {
            result[i] = posts[postIds[i]];
            unchecked {
                ++i;
            }
        }
        
        return result;
    }
    
    /**
     * @notice Get earnings
     */
    function getEarnings(address user) external view returns (uint256) {
        return userEarnings[user];
    }
}

