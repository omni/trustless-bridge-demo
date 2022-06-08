pragma solidity 0.8.14;

import "../../light_client/interfaces/IBeaconLightClient.sol";

interface ITrustlessAMB {
    function lightClient() external view returns (IBeaconLightClient);

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
}
