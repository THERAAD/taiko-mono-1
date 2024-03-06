// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../common/EssentialContract.sol";
import "../L1/ITaikoL1.sol";
import "./IVerifier.sol";
import "./libs/LibPublicInputHash.sol";

/// @notice Verifier interface for RISC Zero receipts of execution.
/// https://github.com/risc0/risc0-ethereum/blob/release-0.7/contracts/src/IRiscZeroVerifier.sol
interface IRiscZeroVerifier {
    /// @notice Verify that the given seal is a valid RISC Zero proof of execution with the
    /// given image ID, post-state digest, and journal digest.
    /// @dev This method additionally ensures that the input hash is all-zeros (i.e. no
    /// committed input), the exit code is (Halted, 0), and there are no assumptions (i.e. the
    /// receipt is unconditional).
    /// @param seal The encoded cryptographic proof (i.e. SNARK).
    /// @param imageId The identifier for the guest program.
    /// @param postStateDigest A hash of the final memory state. Required to run the verifier, but
    /// otherwise can be left unconstrained for most use cases.
    /// @param journalDigest The SHA-256 digest of the journal bytes.
    /// @return true if the receipt passes the verification checks. The return code must be checked.
    function verify(
        bytes calldata seal,
        bytes32 imageId,
        bytes32 postStateDigest,
        bytes32 journalDigest
    )
        external
        view
        returns (bool);
}

/// @title RiscZeroVerifier
/// @custom:security-contact security@taiko.xyz
contract RiscZeroVerifier is EssentialContract, IVerifier {
    /// @notice RISC Zero verifier contract address.
    IRiscZeroVerifier public riscZeroVerifier;
    /// @notice Trusted imageId mapping
    mapping(bytes32 imageId => bool trusted) public isImageTrusted;

    uint256[48] private __gap;

    error RISC_ZERO_INVALID_IMAGE_ID();
    error RISC_ZERO_INVALID_PROOF();

    /// @notice Initializes the contract with the provided address manager.
    /// @param _addressManager The address of the AddressManager.
    /// @param _riscZeroVerifier The address of the risc zero verifier contract.
    function init(address _addressManager, address _riscZeroVerifier) external initializer {
        __Essential_init(address(0), _addressManager);
        riscZeroVerifier = IRiscZeroVerifier(_riscZeroVerifier);
    }

    /// @notice Sets/unsets an the imageId as trusted entity
    /// @param _imageId The id of the image.
    /// @param _trusted True if trusted, false otherwise.
    function setImageIdTrusted(bytes32 _imageId, bool _trusted) external onlyOwner {
        isImageTrusted[_imageId] = _trusted;
    }

    /// @inheritdoc IVerifier
    function verifyProof(
        Context calldata _ctx,
        TaikoData.Transition calldata _tran,
        TaikoData.TierProof calldata _proof
    )
        external
        view
    {
        // Do not run proof verification to contest an existing proof
        if (_ctx.isContesting) return;

        // Decode will throw if not proper length/encoding
        (bytes memory seal, bytes32 imageId, bytes32 postStateDigest) =
            abi.decode(_proof.data, (bytes, bytes32, bytes32));

        if (!isImageTrusted[imageId]) {
            revert RISC_ZERO_INVALID_IMAGE_ID();
        }

        uint64 chainId = ITaikoL1(resolve("taiko", false)).getConfig().chainId;
        bytes32 hash = LibPublicInputHash.hashPublicInputs(
            _tran, address(this), address(0), _ctx.prover, _ctx.metaHash, chainId
        );

        // journalDigest is the sha256 hash of the hashed public input
        bytes32 journalDigest = sha256(bytes.concat(hash));

        if (!riscZeroVerifier.verify(seal, imageId, postStateDigest, journalDigest)) {
            revert RISC_ZERO_INVALID_PROOF();
        }
    }
}