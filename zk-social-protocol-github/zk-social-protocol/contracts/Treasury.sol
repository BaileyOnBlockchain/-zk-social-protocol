// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Treasury
 * @notice M-of-N multi-signature treasury with timelock and governance controls
 * @dev Proposals require M signer approvals + timelock delay before execution.
 *      Auto-executes on final approval if timelock has passed.
 *      Emergency withdraw available for non-native tokens only.
 */
contract Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── State ────────────────────────────────────────────────────────────────

    IERC20 public immutable govToken; // Gas: immutable saves ~2,100 gas per read

    uint256 public requiredSignatures; // M-of-N threshold
    uint256 public timelockDelay;      // Minimum seconds before execution
    address[] public signers;
    mapping(address => bool) public isSigner;

    // ─── Structs ──────────────────────────────────────────────────────────────

    /// @dev Packed for gas — timestamp + deadline fit in uint128, approvalCount in uint8
    struct Proposal {
        address target;
        uint256 amount;
        bytes   data;
        uint128 timestamp;
        uint128 deadline;
        bool    executed;
        uint8   approvalCount;
        mapping(address => bool) approvals;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    // ─── Events ───────────────────────────────────────────────────────────────

    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event RequiredSignaturesUpdated(uint256 oldRequired, uint256 newRequired);
    event ProposalCreated(uint256 indexed proposalId, address indexed target, uint256 amount, bytes data, uint128 deadline);
    event ProposalApproved(uint256 indexed proposalId, address indexed signer);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event TimelockDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed to);

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlySigner() {
        require(isSigner[msg.sender], "Treasury: Not a signer");
        _;
    }

    modifier validProposal(uint256 proposalId) {
        require(proposalId < proposalCount,              "Treasury: Invalid proposal");
        Proposal storage p = proposals[proposalId];
        require(!p.executed,                             "Treasury: Already executed");
        require(block.timestamp <= p.deadline,           "Treasury: Proposal expired");
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    /**
     * @param _govToken          Address of the governance token
     * @param _signers           Initial signer addresses
     * @param _requiredSignatures M-of-N threshold
     * @param _timelockDelay     Minimum delay in seconds (min 1 hour)
     */
    constructor(
        address _govToken,
        address[] memory _signers,
        uint256 _requiredSignatures,
        uint256 _timelockDelay
    ) Ownable(msg.sender) {
        require(_govToken != address(0),                                              "Treasury: Invalid token");
        require(_signers.length > 0,                                                  "Treasury: No signers");
        require(_requiredSignatures > 0 && _requiredSignatures <= _signers.length,    "Treasury: Invalid threshold");
        require(_timelockDelay >= 1 hours,                                            "Treasury: Timelock too short");

        govToken          = IERC20(_govToken);
        requiredSignatures = _requiredSignatures;
        timelockDelay      = _timelockDelay;

        for (uint256 i = 0; i < _signers.length; ) {
            address signer = _signers[i];
            require(signer != address(0),  "Treasury: Invalid signer");
            require(!isSigner[signer],     "Treasury: Duplicate signer");
            isSigner[signer] = true;
            signers.push(signer);
            unchecked { ++i; }
        }
    }

    // ─── Proposal Lifecycle ───────────────────────────────────────────────────

    /**
     * @notice Create a proposal for a token transfer or contract call
     * @param target    Recipient or target contract
     * @param amount    Token amount (0 for pure contract calls)
     * @param data      Calldata (empty for simple transfers)
     * @param deadline  Expiry timestamp (must be > now + timelockDelay, <= now + 30d)
     */
    function createProposal(
        address target,
        uint256 amount,
        bytes calldata data,
        uint256 deadline
    ) external onlySigner nonReentrant returns (uint256) {
        require(target != address(0),                                     "Treasury: Invalid target");
        uint256 _delay = timelockDelay;
        require(deadline > block.timestamp + _delay,                      "Treasury: Deadline too soon");
        require(deadline <= block.timestamp + 30 days,                    "Treasury: Deadline too far");
        require(deadline <= type(uint128).max,                            "Treasury: Deadline overflow");

        uint256 proposalId = proposalCount++;
        Proposal storage p  = proposals[proposalId];
        p.target             = target;
        p.amount             = amount;
        p.data               = data;
        p.timestamp          = uint128(block.timestamp);
        p.deadline           = uint128(deadline);
        p.approvals[msg.sender] = true;
        p.approvalCount      = 1;

        emit ProposalCreated(proposalId, target, amount, data, uint128(deadline));
        emit ProposalApproved(proposalId, msg.sender);

        // SECURITY: Never auto-execute on creation — timelock must always pass.
        return proposalId;
    }

    /**
     * @notice Approve a proposal. Auto-executes if threshold + timelock both met.
     */
    function approveProposal(uint256 proposalId) external onlySigner validProposal(proposalId) {
        Proposal storage p = proposals[proposalId];
        require(!p.approvals[msg.sender], "Treasury: Already approved");

        p.approvals[msg.sender] = true;
        p.approvalCount++;

        emit ProposalApproved(proposalId, msg.sender);

        uint256 _required = requiredSignatures;
        uint256 _delay    = timelockDelay;

        if (p.approvalCount >= _required && block.timestamp >= p.timestamp + _delay) {
            _executeProposal(proposalId);
        }
    }

    /**
     * @notice Manually execute a proposal once threshold + timelock are satisfied
     */
    function executeProposal(uint256 proposalId) external validProposal(proposalId) {
        Proposal storage p = proposals[proposalId];
        require(p.approvalCount >= requiredSignatures, "Treasury: Insufficient approvals");
        require(block.timestamp >= p.timestamp + timelockDelay, "Treasury: Timelock not passed");
        _executeProposal(proposalId);
    }

    function _executeProposal(uint256 proposalId) internal {
        Proposal storage p = proposals[proposalId];
        require(!p.executed, "Treasury: Already executed");

        p.executed = true;

        address _target = p.target;
        uint256 _amount = p.amount;
        bytes memory _data = p.data;

        if (_amount > 0) govToken.safeTransfer(_target, _amount);

        if (_data.length > 0) {
            (bool success, ) = _target.call(_data);
            require(success, "Treasury: Call failed");
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancel a proposal (owner, or anyone after deadline)
     */
    function cancelProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(!p.executed, "Treasury: Already executed");
        require(msg.sender == owner() || block.timestamp > p.deadline, "Treasury: Cannot cancel");
        p.executed = true;
        emit ProposalCancelled(proposalId);
    }

    // ─── Signer Management ────────────────────────────────────────────────────

    function addSigner(address signer) external onlyOwner {
        require(signer != address(0), "Treasury: Invalid signer");
        require(!isSigner[signer],    "Treasury: Already a signer");
        isSigner[signer] = true;
        signers.push(signer);
        emit SignerAdded(signer);
    }

    function removeSigner(address signer) external onlyOwner {
        require(isSigner[signer],               "Treasury: Not a signer");
        require(signers.length > requiredSignatures, "Treasury: Too few signers remaining");
        isSigner[signer] = false;
        for (uint256 i = 0; i < signers.length; ) {
            if (signers[i] == signer) {
                signers[i] = signers[signers.length - 1];
                signers.pop();
                break;
            }
            unchecked { ++i; }
        }
        emit SignerRemoved(signer);
    }

    function setRequiredSignatures(uint256 _required) external onlyOwner {
        require(_required > 0 && _required <= signers.length, "Treasury: Invalid threshold");
        emit RequiredSignaturesUpdated(requiredSignatures, _required);
        requiredSignatures = _required;
    }

    function setTimelockDelay(uint256 _delay) external onlyOwner {
        require(_delay >= 1 hours, "Treasury: Timelock too short");
        emit TimelockDelayUpdated(timelockDelay, _delay);
        timelockDelay = _delay;
    }

    // ─── Emergency ────────────────────────────────────────────────────────────

    /**
     * @notice Emergency withdraw for non-native tokens (owner only)
     * @dev Cannot be used for govToken — use proposals for that
     */
    function emergencyWithdraw(address token, uint256 amount, address to) external onlyOwner {
        require(to != address(0),              "Treasury: Invalid recipient");
        require(token != address(govToken),    "Treasury: Use proposals for gov token");
        IERC20(token).safeTransfer(to, amount);
        emit EmergencyWithdraw(token, amount, to);
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    function getProposal(uint256 proposalId) external view returns (
        address target,
        uint256 amount,
        bytes memory data,
        uint128 timestamp,
        uint128 deadline,
        bool executed,
        uint8 approvalCount,
        bool canExecute
    ) {
        Proposal storage p = proposals[proposalId];
        canExecute = (
            !p.executed &&
            p.approvalCount >= requiredSignatures &&
            block.timestamp >= p.timestamp + timelockDelay &&
            block.timestamp <= p.deadline
        );
        return (p.target, p.amount, p.data, p.timestamp, p.deadline, p.executed, p.approvalCount, canExecute);
    }

    function hasApproved(uint256 proposalId, address signer) external view returns (bool) {
        return proposals[proposalId].approvals[signer];
    }

    function getSigners() external view returns (address[] memory) {
        return signers;
    }

    function getBalance() external view returns (uint256) {
        return govToken.balanceOf(address(this));
    }
}
