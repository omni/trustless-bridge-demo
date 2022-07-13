pragma solidity 0.8.14;

import "./libraries/MPT.sol";
import "../light_client/libraries/Merkle.sol";
import "./TrustlessAMBStorage.sol";
import "./proxy/EIP1967Admin.sol";

contract TrustlessAMB is TrustlessAMBStorage, EIP1967Admin {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    uint256 internal constant SLOTS_PER_HISTORICAL_ROOT = 8192;
    uint256 internal constant HISTORICAL_ROOTS_LIMIT = 16777216;
    bytes32 internal constant EMPTY_MESSAGE_ID = bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    address internal constant EMPTY_ADDRESS = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

    function initialize(address newLightClient, uint256 newMaxGasPerTx, address newOtherSideAMB) external {
        lightClient = IBeaconLightClient(newLightClient);
        maxGasPerTx = newMaxGasPerTx;
        otherSideAMB = newOtherSideAMB;
        otherSideImage = keccak256(abi.encodePacked(newOtherSideAMB));

        messageId = EMPTY_MESSAGE_ID;
        messageSender = EMPTY_ADDRESS;
    }

    function requireToPassMessage(
        address receiver,
        bytes calldata data,
        uint256 gasLimit
    ) external returns (bytes32) {
        require(gasLimit <= maxGasPerTx, "TrustlessAMB: exceed gas limit");
        bytes memory message = abi.encode(
            nonce,
            msg.sender,
            receiver,
            gasLimit,
            data
        );
        bytes32 msgHash = keccak256(message);
        sentMessages[nonce] = msgHash;

        emit SentMessage(msgHash, nonce++, message);

        return msgHash;
    }

    struct ExecuteMessageVars {
        bytes32 msgHash;
        bytes32 stateRoot;
        bytes32 storageRoot;
        uint256 msgNonce;
        address msgSender;
        address msgReceiver;
        uint256 msgGasLimit;
        bytes msgData;
    }

    function executeMessage(
        uint256 sourceSlot,
        bytes calldata message,
        bytes32[] calldata stateRootProof,
        bytes[] calldata accountProof,
        bytes[] calldata storageProof
    ) external returns (bool status) {
        ExecuteMessageVars memory vars;
        vars.msgHash = keccak256(message);
        require(executionStatus[vars.msgHash] == ExecutionStatus.NOT_EXECUTED, "TrustlessAMB: message already executed");

        vars.storageRoot = storageRoot[sourceSlot];
        // if cached root is present, stateRootProof and accountProof can be empty
        if (vars.storageRoot == bytes32(0)) {
            vars.stateRoot = lightClient.stateRoot(sourceSlot);
            require(vars.stateRoot != bytes32(0), "TrustlessAMB: stateRoot is missing");
            require(accountProof.length > 0, "TrustlessAMB: empty account proof");

            {
                // get_generalized_index(BeaconState, 'latest_execution_payload_header', 'state_root')
                uint256 index = 32 + 24;
                index = index * 16 + 2;
                bytes32 executionStateRoot = keccak256(accountProof[0]);
                bytes32 restoredRoot = Merkle.restoreMerkleRoot(executionStateRoot, index, stateRootProof);
                require(vars.stateRoot == restoredRoot, "LightClientChain: invalid payload proof");
            }

            {
                bytes memory accountRLP = MPT.readProof(otherSideImage, accountProof);
                RLPReader.RLPItem[] memory ls = accountRLP.toRlpItem().toList();
                require(ls.length == 4, "TrustlessAMB: invalid account decoded from RLP");
                vars.storageRoot = bytes32(ls[2].toUint());
                storageRoot[sourceSlot] = vars.storageRoot;
                emit VerifiedStorageRoot(sourceSlot, vars.storageRoot);
            }
        }

        (
            vars.msgNonce,
            vars.msgSender,
            vars.msgReceiver,
            vars.msgGasLimit,
            vars.msgData
        ) = abi.decode(message, (uint256, address, address, uint256, bytes));

        {
            // slot of sentMessages[msgNonce] = keccak256(keccak256(vars.msgNonce . 0))
            bytes32 slotKey = keccak256(abi.encode(keccak256(abi.encode(vars.msgNonce, 0))));
            require(vars.storageRoot == keccak256(storageProof[0]), "TrustlessAMB: inconsistent storage root");
            bytes memory slotValue = MPT.readProof(slotKey, storageProof);
            require(bytes32(slotValue.toRlpItem().toUint()) == vars.msgHash, "TrustlessAMB: invalid message hash");
        }

        {
            require(messageId == EMPTY_MESSAGE_ID, "TrustlessAMB: different message execution in progress");
            messageId = vars.msgHash;
            messageSender = vars.msgSender;
            // ensure enough gas for the call + 3 SSTORE + event
            require((gasleft() * 63) / 64 > vars.msgGasLimit + 40000, "TrustlessAMB: insufficient gas");
            (status,) = vars.msgReceiver.call{gas: vars.msgGasLimit}(vars.msgData);
            messageId = EMPTY_MESSAGE_ID;
            messageSender = EMPTY_ADDRESS;
        }
        executionStatus[vars.msgHash] = status ? ExecutionStatus.EXECUTION_SUCCEEDED : ExecutionStatus.EXECUTION_FAILED;
        emit ExecutedMessage(vars.msgHash, vars.msgNonce, message, status);
    }

    function executeMessageFromLog(
        uint256 sourceSlot,
        uint256 targetSlot,
        uint256 txIndex,
        uint256 logIndex,
        bytes calldata message,
        bytes32[] calldata receiptsRootProof,
        bytes[] calldata receiptProof
    ) external returns (bool status) {
        bytes32 msgHash = keccak256(message);
        require(executionStatus[msgHash] == ExecutionStatus.NOT_EXECUTED, "TrustlessAMB: message already executed");

        // verify receiptsRoot
        {
            bytes32 stateRoot = lightClient.stateRoot(sourceSlot);
            require(stateRoot != bytes32(0), "TrustlessAMB: stateRoot is missing");

            // costs of merkle root verification (without SSTORE costs) of payload takes:
            // - for the same slot - (9 merkle layers)
            // - for slot within SLOTS_PER_HISTORICAL_ROOT range - (27 merkle layers)
            // - for any ancient slot - (53 merkle layers)
            uint256 index;
            if (targetSlot == sourceSlot) {
                // get_generalized_index(BeaconState, 'latest_execution_payload_header', 'receipts_root')
                index = 32 + 24;
                index = index * 16 + 3;
            } else if (targetSlot + SLOTS_PER_HISTORICAL_ROOT <= sourceSlot) {
                // concat_generalized_indices(
                //   get_generalized_index(BeaconState, 'historical_roots', targetSlot / SLOTS_PER_HISTORICAL_ROOT)
                //   get_generalized_index(HistoricalBatch, 'state_roots', targetSlot % SLOTS_PER_HISTORICAL_ROOT)
                //   get_generalized_index(BeaconState, 'latest_execution_payload_header', 'receipts_root')
                // ) = concat_generalized_indices(
                //   32 + 7,
                //   2 + 0,
                //   HISTORICAL_ROOTS_LIMIT + targetSlot / SLOTS_PER_HISTORICAL_ROOT,
                //   2 + 1,
                //   SLOTS_PER_HISTORICAL_ROOT + targetSlot % SLOTS_PER_HISTORICAL_ROOT,
                //   32 + 24,
                //   16 + 3
                // )
                index = 32 + 7;
                index = index * 2 + 0;
                index = index * HISTORICAL_ROOTS_LIMIT + targetSlot / SLOTS_PER_HISTORICAL_ROOT;
                index = index * 2 + 1;
                index = index * SLOTS_PER_HISTORICAL_ROOT + targetSlot % SLOTS_PER_HISTORICAL_ROOT;
                index = index * 32 + 24;
                index = index * 16 + 3;
            } else if (targetSlot < sourceSlot) {
                // concat_generalized_indices(
                //   get_generalized_index(BeaconState, 'state_roots', targetSlot % SLOTS_PER_HISTORICAL_ROOT),
                //   get_generalized_index(BeaconState, 'latest_execution_payload_header', 'receipts_root')
                // ) = concat_generalized_indices(
                //   32 + 6,
                //   SLOTS_PER_HISTORICAL_ROOT + targetSlot % SLOTS_PER_HISTORICAL_ROOT,
                //   32 + 24,
                //   16 + 3
                // )
                index = 32 + 6;
                index = index * SLOTS_PER_HISTORICAL_ROOT + targetSlot % SLOTS_PER_HISTORICAL_ROOT;
                index = index * 32 + 24;
                index = index * 16 + 3;
            } else {
                revert("TrustlessAMB: invalid target slot");
            }
            bytes32 receiptsRoot = keccak256(receiptProof[0]);
            bytes32 restoredRoot = Merkle.restoreMerkleRoot(receiptsRoot, index, receiptsRootProof);
            require(stateRoot == restoredRoot, "TrustlessAMB: invalid receipts root proof");
        }

        {
            bytes32 key = rlpIndex(txIndex);
            bytes memory receiptRLP = MPT.readProof(key, receiptProof);
            RLPReader.RLPItem memory item = receiptRLP.toRlpItem();
            if (!item.isList()) {
                item.memPtr++;
                item.len--;
            }
            RLPReader.RLPItem[] memory ls = item.toList();
            require(ls.length == 4, "TrustlessAMB: invalid receipt decoded from RLP");
            ls = ls[3].toList();
            require(logIndex < ls.length, "TrustlessAMB: missing log index");
            ls = ls[logIndex].toList();
            require(ls.length == 3, "TrustlessAMB: invalid log decoded from RLP");
            require(otherSideAMB == ls[0].toAddress(), "TrustlessAMB: invalid log origin");
            RLPReader.RLPItem[] memory rlpTopics = ls[1].toList();
            require(rlpTopics.length == 3, "TruslessAMB: different topics count expected");
            require(bytes32(rlpTopics[0].toUintStrict()) == keccak256("SentMessage(bytes32,uint256,bytes)"), "TruslessAMB: different event signature expected");
            require(bytes32(rlpTopics[1].toUintStrict()) == msgHash, "TruslessAMB: different msgHash in log expected");
        }

        (
            uint256 msgNonce,
            address sender,
            address receiver,
            uint256 gasLimit,
            bytes memory data
        ) = abi.decode(message, (uint256, address, address, uint256, bytes));

        {
            require(messageId == EMPTY_MESSAGE_ID, "TrustlessAMB: different message execution in progress");
            messageId = msgHash;
            messageSender = sender;
            // ensure enough gas for the call + 3 SSTORE + event
            require((gasleft() * 63) / 64 > gasLimit + 40000, "TrustlessAMB: insufficient gas");
            (status,) = receiver.call{gas: gasLimit}(data);
            messageId = EMPTY_MESSAGE_ID;
            messageSender = EMPTY_ADDRESS;
        }
        executionStatus[msgHash] = status ? ExecutionStatus.EXECUTION_SUCCEEDED : ExecutionStatus.EXECUTION_FAILED;
        emit ExecutedMessage(msgHash, msgNonce, message, status);
    }

    function rlpIndex(uint256 v) internal pure returns (bytes32) {
        if (v == 0) {
            return bytes32(uint256(0x80 << 248));
        } else if (v < 128) {
            return bytes32(uint256(0x80 << 248));
        } else if (v < 256) {
            return bytes32(uint256(0x81 << 248 | v << 240));
        } else {
            return bytes32(uint256(0x82 << 248 | v << 232));
        }
    }

    function head() external view returns (uint256) {
        return lightClient.head();
    }

    function messageCallStatus(bytes32 _messageId) external view returns (bool) {
        return executionStatus[_messageId] == ExecutionStatus.EXECUTION_SUCCEEDED;
    }
}
