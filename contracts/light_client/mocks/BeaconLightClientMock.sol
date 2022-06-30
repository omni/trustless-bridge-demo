pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

import "../interfaces/IBeaconLightClient.sol";

contract BeaconLightClientMock {
    uint256 public head; // slot of latest known block
    mapping(uint256 => IBeaconLightClient.StorageBeaconBlockHeader) public headers; // slot => header

    function setHead(uint256 slot, bytes32 root, bytes32 stateRoot) external {
        head = slot;
        headers[slot] = IBeaconLightClient.StorageBeaconBlockHeader(root, stateRoot);
    }

    function stateRoot(uint256 slot) external view returns (bytes32) {
        return headers[slot].stateRoot;
    }
}
