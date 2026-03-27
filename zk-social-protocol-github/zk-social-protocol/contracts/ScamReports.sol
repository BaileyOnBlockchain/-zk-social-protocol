// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ScamReports
 * @notice On-chain scam reporting and trust score system
 * @dev Stores reports and calculates trust scores for wallet addresses
 */
contract ScamReports is Ownable, ReentrancyGuard {
    // Report structure
    struct Report {
        uint256 id;
        address reportedAddress;
        address reporterAddress;
        string reason;
        string evidence;
        uint256 timestamp;
        bool verified;
        bool dismissed;
    }
    
    // Trust score structure
    struct TrustScore {
        address wallet;
        uint256 score; // 0-100, lower is more suspicious
        uint256 totalReports;
        uint256 verifiedReports;
        uint256 lastUpdated;
    }
    
    // Storage
    mapping(uint256 => Report) public reports;
    mapping(address => uint256[]) public reportsByAddress; // reportedAddress => reportIds[]
    mapping(address => uint256[]) public reportsByReporter; // reporterAddress => reportIds[]
    mapping(address => TrustScore) public trustScores;
    
    uint256 public reportCounter;
    
    // Events
    event ReportSubmitted(
        uint256 indexed reportId,
        address indexed reportedAddress,
        address indexed reporterAddress,
        string reason
    );
    
    event ReportVerified(uint256 indexed reportId, address indexed reportedAddress);
    event ReportDismissed(uint256 indexed reportId);
    event TrustScoreUpdated(address indexed wallet, uint256 newScore);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Submit a scam report
     * @param reportedAddress The wallet address being reported
     * @param reason Description of the scam/suspicious activity
     * @param evidence Optional evidence (links, transaction hashes, etc.)
     */
    function submitReport(
        address reportedAddress,
        string calldata reason,
        string calldata evidence
    ) external nonReentrant {
        require(reportedAddress != address(0), "ScamReports: Invalid address");
        require(bytes(reason).length > 0, "ScamReports: Reason required");
        require(bytes(reason).length <= 1000, "ScamReports: Reason too long");
        require(bytes(evidence).length <= 500, "ScamReports: Evidence too long");
        require(reportedAddress != msg.sender, "ScamReports: Cannot report yourself");
        
        uint256 reportId = reportCounter++;
        
        reports[reportId] = Report({
            id: reportId,
            reportedAddress: reportedAddress,
            reporterAddress: msg.sender,
            reason: reason,
            evidence: evidence,
            timestamp: block.timestamp,
            verified: false,
            dismissed: false
        });
        
        reportsByAddress[reportedAddress].push(reportId);
        reportsByReporter[msg.sender].push(reportId);
        
        // Initialize or update trust score
        TrustScore storage score = trustScores[reportedAddress];
        if (score.wallet == address(0)) {
            score.wallet = reportedAddress;
            score.score = 100; // Start at 100, decrease with reports
            score.totalReports = 0;
            score.verifiedReports = 0;
            score.lastUpdated = block.timestamp;
        }
        
        score.totalReports++;
        _updateTrustScore(reportedAddress);
        
        emit ReportSubmitted(reportId, reportedAddress, msg.sender, reason);
    }
    
    /**
     * @notice Verify a report (owner or moderator only)
     * @param reportId The report ID to verify
     */
    function verifyReport(uint256 reportId) external onlyOwner {
        Report storage report = reports[reportId];
        require(report.id == reportId, "ScamReports: Report does not exist");
        require(!report.verified && !report.dismissed, "ScamReports: Report already processed");
        
        report.verified = true;
        
        TrustScore storage score = trustScores[report.reportedAddress];
        score.verifiedReports++;
        _updateTrustScore(report.reportedAddress);
        
        emit ReportVerified(reportId, report.reportedAddress);
    }
    
    /**
     * @notice Dismiss a report (owner or moderator only)
     * @param reportId The report ID to dismiss
     */
    function dismissReport(uint256 reportId) external onlyOwner {
        Report storage report = reports[reportId];
        require(report.id == reportId, "ScamReports: Report does not exist");
        require(!report.verified && !report.dismissed, "ScamReports: Report already processed");
        
        report.dismissed = true;
        
        emit ReportDismissed(reportId);
    }
    
    /**
     * @notice Get a report by ID
     */
    function getReport(uint256 reportId) external view returns (Report memory) {
        return reports[reportId];
    }
    
    /**
     * @notice Get all reports for an address
     */
    function getReportsForAddress(address wallet) external view returns (uint256[] memory) {
        return reportsByAddress[wallet];
    }
    
    /**
     * @notice Get trust score for an address
     */
    function getTrustScore(address wallet) external view returns (TrustScore memory) {
        return trustScores[wallet];
    }
    
    /**
     * @notice Get multiple reports
     */
    function getReports(uint256[] calldata reportIds) external view returns (Report[] memory) {
        Report[] memory result = new Report[](reportIds.length);
        for (uint256 i = 0; i < reportIds.length; i++) {
            result[i] = reports[reportIds[i]];
        }
        return result;
    }
    
    /**
     * @notice Update trust score based on reports
     * @dev Lower score = more suspicious (0-100 scale)
     */
    function _updateTrustScore(address wallet) internal {
        TrustScore storage score = trustScores[wallet];
        
        // Calculate score: 100 - (verifiedReports * 10) - (unverifiedReports * 2)
        // Minimum score is 0
        uint256 unverifiedReports = score.totalReports > score.verifiedReports 
            ? score.totalReports - score.verifiedReports 
            : 0;
        uint256 penalty = (score.verifiedReports * 10) + (unverifiedReports * 2);
        score.score = penalty >= 100 ? 0 : 100 - penalty;
        
        score.lastUpdated = block.timestamp;
        emit TrustScoreUpdated(wallet, score.score);
    }
    
    /**
     * @notice Get total number of reports
     */
    function getTotalReports() external view returns (uint256) {
        return reportCounter;
    }
}

