pragma solidity 0.8.14;

interface IBeaconLightClient {
    struct BestValidUpdate {
        uint64 slot;
        uint64 signatures;
        uint64 timeout;
        bytes32 root;
        bytes32 stateRoot;
    }

    struct StorageBeaconBlockHeader {
        bytes32 root;
        bytes32 stateRoot;
    }

    function head() external view returns (uint256);

    function headers(uint256 slot) external view returns (StorageBeaconBlockHeader memory);

    function bestValidUpdate() external view returns (BestValidUpdate memory);

    function stateRoot(uint256 slot) external view returns (bytes32);
}
