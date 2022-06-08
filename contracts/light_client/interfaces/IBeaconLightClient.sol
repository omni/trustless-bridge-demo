pragma solidity 0.8.14;

interface IBeaconLightClient {
    function headSlot() external view returns (uint256);

    function executionStateRootByBlockNumber(uint256 blockNumber) external view returns (bytes32);
}
