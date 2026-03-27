// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title StakingVault
 * @notice Yearn-style staking vault for $PRIV tokens
 * @dev Users stake PRIV tokens and earn APY from platform fees
 */
contract StakingVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    IERC20 public immutable privToken;
    
    // Staking parameters
    uint256 public totalStaked;
    uint256 public totalRewards;
    uint256 public apy; // APY in basis points (e.g., 1250 = 12.5%)
    
    // User staking data
    struct StakeInfo {
        uint256 amount;
        uint256 stakedAt;
        uint256 lastClaimed;
    }
    
    mapping(address => StakeInfo) public stakes;
    
    // Events
    event Staked(address indexed user, uint256 amount, uint256 timestamp);
    event Unstaked(address indexed user, uint256 amount, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 amount);
    event APYUpdated(uint256 newAPY);
    event RewardsDeposited(uint256 amount);
    
    constructor(address _privToken, uint256 _initialAPY) Ownable(msg.sender) {
        privToken = IERC20(_privToken);
        apy = _initialAPY; // e.g., 1250 = 12.5%
    }
    
    /**
     * @notice Stake PRIV tokens
     * @param amount Amount to stake
     */
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: Amount must be greater than 0");
        
        privToken.safeTransferFrom(msg.sender, address(this), amount);
        
        StakeInfo storage userStake = stakes[msg.sender];
        if (userStake.amount > 0) {
            // Claim existing rewards before adding more
            _claimRewards(msg.sender);
        }
        
        userStake.amount += amount;
        userStake.stakedAt = block.timestamp;
        userStake.lastClaimed = block.timestamp;
        
        totalStaked += amount;
        
        emit Staked(msg.sender, amount, block.timestamp);
    }
    
    /**
     * @notice Unstake PRIV tokens
     * @param amount Amount to unstake
     */
    function unstake(uint256 amount) external nonReentrant {
        StakeInfo storage userStake = stakes[msg.sender];
        require(userStake.amount >= amount, "StakingVault: Insufficient staked amount");
        
        // Claim rewards before unstaking
        _claimRewards(msg.sender);
        
        userStake.amount -= amount;
        totalStaked -= amount;
        
        privToken.safeTransfer(msg.sender, amount);
        
        emit Unstaked(msg.sender, amount, block.timestamp);
    }
    
    /**
     * @notice Claim staking rewards
     */
    function claimRewards() external nonReentrant {
        _claimRewards(msg.sender);
    }
    
    /**
     * @notice Calculate pending rewards for a user
     * @dev Prevents overflow by checking timeStaked bounds
     */
    function calculateRewards(address user) public view returns (uint256) {
        StakeInfo memory userStake = stakes[user];
        if (userStake.amount == 0) return 0;
        
        uint256 timeStaked = block.timestamp - userStake.lastClaimed;
        // Prevent overflow: cap timeStaked to 10 years max
        if (timeStaked > 3650 days) {
            timeStaked = 3650 days;
        }
        
        uint256 annualReward = (userStake.amount * apy) / 10000;
        uint256 pendingReward = (annualReward * timeStaked) / 365 days;
        
        return pendingReward;
    }
    
    /**
     * @notice Internal function to claim rewards
     * @dev Checks available balance for rewards (excluding staked amounts)
     */
    function _claimRewards(address user) internal {
        uint256 rewards = calculateRewards(user);
        if (rewards == 0) return;
        
        StakeInfo storage userStake = stakes[user];
        userStake.lastClaimed = block.timestamp;
        
        // Ensure contract has enough tokens for rewards (available = total - staked)
        uint256 availableBalance = privToken.balanceOf(address(this));
        require(
            availableBalance >= totalStaked + rewards,
            "StakingVault: Insufficient rewards"
        );
        
        privToken.safeTransfer(user, rewards);
        totalRewards += rewards;
        
        emit RewardsClaimed(user, rewards);
    }
    
    /**
     * @notice Get user's staking info
     */
    function getUserStake(address user) external view returns (StakeInfo memory) {
        return stakes[user];
    }
    
    /**
     * @notice Update APY (owner only)
     */
    function setAPY(uint256 _newAPY) external onlyOwner {
        require(_newAPY <= 10000, "StakingVault: APY cannot exceed 100%");
        apy = _newAPY;
        emit APYUpdated(_newAPY);
    }
    
    /**
     * @notice Deposit rewards into vault (owner only)
     * @dev Called when platform fees are collected
     */
    function depositRewards(uint256 amount) external onlyOwner {
        privToken.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsDeposited(amount);
    }
    
    /**
     * @notice Get current APY
     */
    function getAPY() external view returns (uint256) {
        return apy;
    }
}

