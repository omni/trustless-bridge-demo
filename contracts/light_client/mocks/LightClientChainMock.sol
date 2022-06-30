pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

contract LightClientChainMock {
    uint256 public head; // slot of latest known block
    mapping(uint256 => bytes32) public stateRoot; // slot => header
    mapping(uint256 => bytes32) public receiptsRoot; // slot => header

    function setHead(uint256 blockNumber, bytes32 _stateRoot, bytes32 _receiptsRoot) external {
        head = blockNumber;
        stateRoot[blockNumber] = _stateRoot;
        receiptsRoot[blockNumber] = _receiptsRoot;
    }
}
