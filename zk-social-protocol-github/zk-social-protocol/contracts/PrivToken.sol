// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PrivToken ($PRIV)
 * @notice ERC-20 utility token for tipping, staking, and governance
 * @dev 1B hard cap, per-address mint cap for anti-sybil protection
 */
contract PrivToken is ERC20, ERC20Burnable, Ownable, ReentrancyGuard {

    // ─── Constants ────────────────────────────────────────────────────────────

    uint256 public constant MAX_SUPPLY            = 1_000_000_000 * 10**18;
    uint256 public constant MINT_CAP_PER_ADDRESS  = 1_000         * 10**18;

    // ─── State ────────────────────────────────────────────────────────────────

    mapping(address => uint256) public mintedAmount;

    // ─── Events ───────────────────────────────────────────────────────────────

    event TokensMinted(address indexed to, uint256 amount, string reason);

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor() ERC20("Priv Token", "PRIV") Ownable(msg.sender) {
        _mint(msg.sender, 100_000_000 * 10**18); // 100M initial distribution
    }

    // ─── Minting ──────────────────────────────────────────────────────────────

    /**
     * @notice Mint tokens to a user (e.g. for posting, engagement rewards)
     * @param to        Recipient address
     * @param amount    Amount to mint (wei)
     * @param reason    Reason string for tracking
     */
    function mint(address to, uint256 amount, string calldata reason) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY,                     "PrivToken: Max supply exceeded");
        require(mintedAmount[to] + amount <= MINT_CAP_PER_ADDRESS,        "PrivToken: Mint cap exceeded");

        mintedAmount[to] += amount;
        _mint(to, amount);

        emit TokensMinted(to, amount, reason);
    }

    /**
     * @notice Batch mint to multiple addresses in one tx
     * @param recipients  Array of recipient addresses
     * @param amounts     Corresponding amounts (wei)
     * @param reason      Shared reason string
     */
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string calldata reason
    ) external onlyOwner {
        require(recipients.length == amounts.length, "PrivToken: Array length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            require(totalSupply() + amounts[i] <= MAX_SUPPLY,
                "PrivToken: Max supply exceeded");
            require(mintedAmount[recipients[i]] + amounts[i] <= MINT_CAP_PER_ADDRESS,
                "PrivToken: Mint cap exceeded");

            mintedAmount[recipients[i]] += amounts[i];
            _mint(recipients[i], amounts[i]);
        }

        emit TokensMinted(address(0), 0, reason); // Batch event
    }
}
