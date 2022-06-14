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
        bytes[] calldata accountProof,
        bytes[] calldata storageProof
    ) external returns (bool);

    // Legacy interfaces from the previous trustfull version of AMB

    function messageCallStatus(bytes32 _messageId) external view returns (bool);
}
