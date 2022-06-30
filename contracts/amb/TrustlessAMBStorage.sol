pragma solidity 0.8.14;

import "./interfaces/ITrustlessAMB.sol";

abstract contract TrustlessAMBStorage is ITrustlessAMB {
    mapping(uint256 => bytes32) public sentMessages;
    mapping(bytes32 => ExecutionStatus) public executionStatus;

    ILightClientChain public chain;
    address public otherSideAMB;
    bytes32 public otherSideImage;

    uint256 public nonce;
    uint256 public maxGasPerTx;

    address public messageSender;
    bytes32 public messageId;
}
