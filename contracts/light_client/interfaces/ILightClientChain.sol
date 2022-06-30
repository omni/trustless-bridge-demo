pragma solidity 0.8.14;

interface ILightClientChain {
    struct ExecutionPayloadHeader {
        bytes32 parentHash;
        address feeRecipient;
        bytes32 stateRoot;
        bytes32 receiptsRoot;
        bytes32 logsBloomRoot;
        bytes32 prevRandao;
        uint64 blockNumber;
        uint64 gasLimit;
        uint64 gasUsed;
        uint64 timestamp;
        bytes32 extraDataRoot;
        uint256 baseFeePerGas;
        bytes32 blockHash;
        bytes32 transactionsRoot;
    }

    function head() external view returns (uint256);

    function stateRoot(uint256 blockNumber) external view returns (bytes32);

    function receiptsRoot(uint256 blockNumber) external view returns (bytes32);

    function headers(uint256 blockNumber) external view returns (ExecutionPayloadHeader memory);
}
