// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@semaphore-protocol/contracts/base/SemaphoreGroups.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IEZKLVerifier.sol";

/**
 * @title PrivNetSemaphore
 * @notice Main contract for anonymous posting with optional AI moderation via EZKL
 * @dev Uses Semaphore for anonymous posts, adds EZKL verification for toxicity checks
 */
contract PrivNetSemaphore is SemaphoreGroups, Ownable {
    ISemaphore public semaphore;
    IEZKLVerifier public ezklVerifier;

    uint256 public groupId;
    uint256 public toxicityThreshold = 0.5 * 1e18; // 0.5 in 18 decimals (50% threshold)
    bool public moderationEnabled = true;

    // Events
    event AnonymousPost(uint256 indexed signal, uint256 indexed topic);
    event ModeratedPost(address indexed user, uint256 indexed signal, uint256 indexed topic);
    event ToxicityThresholdUpdated(uint256 newThreshold);
    event ModerationToggled(bool enabled);

    constructor(address _semaphore, address _ezklVerifier) Ownable(msg.sender) {
        semaphore = ISemaphore(_semaphore);
        ezklVerifier = IEZKLVerifier(_ezklVerifier);
        // Create group via semaphore contract and store the groupId
        groupId = semaphore.createGroup(address(this));
    }

    /**
     * @notice Join the PrivNet Semaphore group
     * @param identityCommitment User's Semaphore identity commitment
     */
    function joinGroup(uint256 identityCommitment) external {
        semaphore.addMember(groupId, identityCommitment);
    }

    /**
     * @notice Post anonymously with Semaphore proof only
     * @param proof Semaphore proof struct
     */
    function postAnonymously(ISemaphore.SemaphoreProof calldata proof) external {
        // validateProof handles nullifier saving and proof verification
        semaphore.validateProof(groupId, proof);
        emit AnonymousPost(proof.message, proof.scope);
    }

    /**
     * @notice Post with AI moderation (EZKL proof verification)
     * @param semaphoreProof Semaphore proof struct
     * @param ezklProof EZKL proof that toxicity < threshold
     * @param publicInputs Public inputs for EZKL: [signalHash, toxicityScore]
     */
    function postWithModeration(
        ISemaphore.SemaphoreProof calldata semaphoreProof,
        bytes calldata ezklProof,
        uint256[] calldata publicInputs
    ) external {
        // Verify Semaphore proof (user is in group)
        semaphore.validateProof(groupId, semaphoreProof);

        // If moderation is enabled, verify EZKL proof
        if (moderationEnabled) {
            require(
                ezklVerifier.verifyProof(ezklProof, publicInputs),
                "PrivNetSemaphore: EZKL proof verification failed"
            );
            
            // Verify toxicity score is below threshold (publicInputs[1] should be toxicity score)
            require(
                publicInputs.length >= 2 && publicInputs[1] < toxicityThreshold,
                "PrivNetSemaphore: Content toxicity exceeds threshold"
            );
        }

        emit ModeratedPost(msg.sender, semaphoreProof.message, semaphoreProof.scope);
    }

    /**
     * @notice Update toxicity threshold (owner only)
     * @param newThreshold New threshold in 18 decimals (e.g., 0.5e18 = 50%)
     */
    function setToxicityThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold <= 1e18, "PrivNetSemaphore: Threshold cannot exceed 100%");
        toxicityThreshold = newThreshold;
        emit ToxicityThresholdUpdated(newThreshold);
    }

    /**
     * @notice Toggle moderation on/off (owner only)
     * @param enabled Whether moderation should be enabled
     */
    function setModerationEnabled(bool enabled) external onlyOwner {
        moderationEnabled = enabled;
        emit ModerationToggled(enabled);
    }
}

