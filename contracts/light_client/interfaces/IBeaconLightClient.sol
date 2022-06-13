pragma solidity 0.8.14;

interface IBeaconLightClient {
    struct HeadPointer {
        uint64 slot;
        uint64 executionBlockNumber;
    }

    function head() external view returns (HeadPointer memory);

    function executionStateRootByBlockNumber(uint256 blockNumber) external view returns (bytes32);
}
