// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IEZKLVerifier
 * @notice Interface for EZKL proof verification (toxicity classifier)
 * @dev This is a placeholder interface. Replace with actual EZKL verifier after model proving.
 * 
 * EZKL Setup Steps:
 * 1. Train DistilBERT toxicity classifier on dataset
 * 2. Export model to ONNX format
 * 3. Generate EZKL circuit from ONNX model
 * 4. Run trusted setup (powersOfTau + phase2)
 * 5. Deploy verifier contract from EZKL output
 * 6. Update EZKL_VERIFIER_ADDRESS in deployment script
 */
interface IEZKLVerifier {
    /**
     * @notice Verify EZKL proof that toxicity score is below threshold
     * @param proof The EZKL proof bytes
     * @param publicInputs Public inputs (e.g., [signalHash, toxicityScore])
     * @return verified True if proof is valid and toxicity < threshold
     */
    function verifyProof(
        bytes calldata proof,
        uint256[] calldata publicInputs
    ) external view returns (bool verified);
}

