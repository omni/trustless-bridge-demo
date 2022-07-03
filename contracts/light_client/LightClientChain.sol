pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

import "./interfaces/IBeaconLightClient.sol";
import "./interfaces/ILightClientChain.sol";
import "./libraries/LittleEndian.sol";
import "./libraries/Merkle.sol";

contract LightClientChain {
    IBeaconLightClient public beaconLightClient;

    uint256 internal constant SLOTS_PER_HISTORICAL_ROOT = 8192;
    uint256 internal constant HISTORICAL_ROOTS_LIMIT = 16777216;

    event VerifiedExecutionBlock(uint256 indexed blockNumber, bytes32 blockHash);

    constructor(IBeaconLightClient client) {
        beaconLightClient = client;
    }

    mapping(uint256 => ILightClientChain.ExecutionPayloadHeader) public headers;
    uint256 public head;

    function stateRoot(uint256 blockNumber) external view returns (bytes32) {
        return headers[blockNumber].stateRoot;
    }

    function receiptsRoot(uint256 blockNumber) external view returns (bytes32) {
        return headers[blockNumber].receiptsRoot;
    }

    function verifyExecutionPayload(
        uint256 slot,
        uint256 targetSlot,
        ILightClientChain.ExecutionPayloadHeader memory payload,
        bytes32[] memory payloadProof
    ) public {
        bytes32 stateRoot = beaconLightClient.stateRoot(slot);
        require(stateRoot != bytes32(0), "LightClientChain: empty beacon header state root");
        require(targetSlot <= slot, "LightClientChain: invalid target slot");

        bytes32 root = hashExecutionPayload(payload);

        // costs of merkle root verification (without SSTORE costs) of payload takes:
        // - for the same slot - ~50k gas (5 merkle layers)
        // - for slot within SLOTS_PER_HISTORICAL_ROOT range - ~74k gas (23 merkle layers)
        // - for any ancient slot - ~104k gas (49 merkle layers)
        uint256 index = 32 + 24;
        if (targetSlot + SLOTS_PER_HISTORICAL_ROOT <= slot) {
            // concat_generalized_indices(
            //   get_generalized_index(BeaconState, 'historical_roots', targetSlot / SLOTS_PER_HISTORICAL_ROOT)
            //   get_generalized_index(HistoricalBatch, 'state_roots', targetSlot % SLOTS_PER_HISTORICAL_ROOT)
            //   get_generalized_index(BeaconState, 'latest_execution_payload_header')
            // ) = concat_generalized_indices(
            //   32 + 7,
            //   2 + 0,
            //   HISTORICAL_ROOTS_LIMIT + targetSlot / SLOTS_PER_HISTORICAL_ROOT,
            //   2 + 1,
            //   SLOTS_PER_HISTORICAL_ROOT + targetSlot % SLOTS_PER_HISTORICAL_ROOT,
            //   32 + 24
            // )
            index = 39;
            index = index * 2 + 0;
            index = index * HISTORICAL_ROOTS_LIMIT + targetSlot / SLOTS_PER_HISTORICAL_ROOT;
            index = index * 2 + 1;
            index = index * SLOTS_PER_HISTORICAL_ROOT + targetSlot % SLOTS_PER_HISTORICAL_ROOT;
            index = index * 32 + 24;
        } else if (targetSlot < slot) {
            // concat_generalized_indices(
            //   get_generalized_index(BeaconState, 'state_roots', targetSlot % SLOTS_PER_HISTORICAL_ROOT),
            //   get_generalized_index(BeaconState, 'latest_execution_payload_header')
            // ) = concat_generalized_indices(
            //   32 + 6,
            //   SLOTS_PER_HISTORICAL_ROOT + targetSlot % SLOTS_PER_HISTORICAL_ROOT,
            //   32 + 24
            // )
            index = 38;
            index = index * SLOTS_PER_HISTORICAL_ROOT + targetSlot % SLOTS_PER_HISTORICAL_ROOT;
            index = index * 32 + 24;
            index = 32 * (SLOTS_PER_HISTORICAL_ROOT * 38 + targetSlot % SLOTS_PER_HISTORICAL_ROOT) + 24;
        }

        bytes32 restoredRoot = Merkle.restoreMerkleRoot(root, index, payloadProof);
        require(stateRoot == restoredRoot, "LightClientChain: invalid payload proof");

        if (head < payload.blockNumber) {
            head = payload.blockNumber;
        }
        headers[payload.blockNumber] = payload;

        emit VerifiedExecutionBlock(payload.blockNumber, payload.blockHash);
    }

    function hashExecutionPayload(ILightClientChain.ExecutionPayloadHeader memory payload) public view returns (bytes32) {
        bytes32 tmp1 = sha256(abi.encodePacked(payload.parentHash, payload.feeRecipient, uint96(0)));
        bytes32 tmp2 = sha256(abi.encodePacked(payload.stateRoot, payload.receiptsRoot));
        bytes32 tmp3 = sha256(abi.encodePacked(payload.logsBloomRoot, payload.prevRandao));
        bytes32 tmp4 = sha256(abi.encodePacked(LittleEndian.encode(payload.blockNumber), LittleEndian.encode(payload.gasLimit)));
        bytes32 tmp5 = sha256(abi.encodePacked(LittleEndian.encode(payload.gasUsed), LittleEndian.encode(payload.timestamp)));
        bytes32 tmp6 = sha256(abi.encodePacked(payload.extraDataRoot, LittleEndian.encode(payload.baseFeePerGas)));
        bytes32 tmp7 = sha256(abi.encodePacked(payload.blockHash, payload.transactionsRoot));
        tmp1 = sha256(abi.encodePacked(tmp1, tmp2));
        tmp3 = sha256(abi.encodePacked(tmp3, tmp4));
        tmp5 = sha256(abi.encodePacked(tmp5, tmp6));
        tmp7 = sha256(abi.encodePacked(tmp7, bytes32(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b)));
        tmp1 = sha256(abi.encodePacked(tmp1, tmp3));
        tmp5 = sha256(abi.encodePacked(tmp5, tmp7));
        return sha256(abi.encodePacked(tmp1, tmp5));
    }
}
