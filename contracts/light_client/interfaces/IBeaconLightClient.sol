pragma solidity 0.8.14;

interface IBeaconLightClient {
    struct HeadPointer {
        uint64 slot;
        uint64 executionBlockNumber;
    }

    struct BestValidUpdate {
        uint64 slot;
        uint64 executionBlockNumber;
        uint64 signatures;
        uint64 timeout;
        bytes32 root;
        bytes32 stateRoot;
        bytes32 executionStateRoot;
    }

    struct StorageBeaconBlockHeader {
        bytes32 root;
        bytes32 stateRoot;
        bytes32 executionStateRoot;
    }

    function head() external view returns (HeadPointer memory);

    function headers(uint256 slot) external view returns (StorageBeaconBlockHeader memory);

    function bestValidUpdate() external view returns (BestValidUpdate memory);

    function executionStateRootByBlockNumber(uint256 blockNumber) external view returns (bytes32);
}
