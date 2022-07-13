pragma solidity 0.8.14;

import "../../light_client/interfaces/IBeaconLightClient.sol";

interface ITrustlessAMB {
    enum ExecutionStatus {
        NOT_EXECUTED,       // b'00
        INVALID,            // b'01
        EXECUTION_FAILED,   // b'10
        EXECUTION_SUCCEEDED // b'11
    }
    event SentMessage(bytes32 indexed msgHash, uint256 indexed nonce, bytes message);
    event ExecutedMessage(bytes32 indexed msgHash, uint256 indexed nonce, bytes message, bool status);
    event VerifiedStorageRoot(uint256 indexed slot, bytes32 indexed storageRoot);

    function lightClient() external view returns (IBeaconLightClient);

    function messageId() external view returns (bytes32);

    function messageSender() external view returns (address);

    function requireToPassMessage(
        address receiver,
        bytes calldata message,
        uint256 gasLimit
    ) external returns (bytes32);

    function executeMessage(
        uint256 sourceBlock,
        bytes calldata message,
        bytes32[] calldata stateRootProof,
        bytes[] calldata accountProof,
        bytes[] calldata storageProof
    ) external returns (bool);

    function executeMessageFromLog(
        uint256 sourceSlot,
        uint256 targetSlot,
        uint256 txIndex,
        uint256 logIndex,
        bytes calldata message,
        bytes32[] calldata receiptsRootProof,
        bytes[] calldata receiptProof
    ) external returns (bool);

    // Legacy interfaces from the previous trustfull version of AMB

    function messageCallStatus(bytes32 _messageId) external view returns (bool);
}
