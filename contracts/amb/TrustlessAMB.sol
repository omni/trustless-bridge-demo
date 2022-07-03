pragma solidity 0.8.14;

import "./libraries/MPT.sol";
import "./TrustlessAMBStorage.sol";
import "./proxy/EIP1967Admin.sol";
import "../light_client/LightClientChain.sol";

contract TrustlessAMB is TrustlessAMBStorage, EIP1967Admin {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    function initialize(address newChain, uint256 newMaxGasPerTx, address newOtherSideAMB) external {
        chain = ILightClientChain(newChain);
        maxGasPerTx = newMaxGasPerTx;
        otherSideAMB = newOtherSideAMB;
        otherSideImage = keccak256(abi.encodePacked(newOtherSideAMB));
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
    }

    function executeMessage(
        uint256 sourceBlock,
        bytes calldata message,
        bytes[] calldata accountProof,
        bytes[] calldata storageProof
    ) external returns (bool status) {
        ExecuteMessageVars memory vars;
        vars.msgHash = keccak256(message);
        require(executionStatus[vars.msgHash] == ExecutionStatus.NOT_EXECUTED, "TrustlessAMB: message already executed");

        vars.stateRoot = chain.stateRoot(sourceBlock);
        require(vars.stateRoot != bytes32(0), "TrustlessAMB: stateRoot is missing");

        {
            bytes memory accountRLP = MPT.verifyMPTProof(vars.stateRoot, otherSideImage, accountProof);
            RLPReader.RLPItem[] memory ls = accountRLP.toRlpItem().toList();
            require(ls.length == 4, "TrustlessAMB: invalid account decoded from RLP");
            vars.storageRoot = bytes32(ls[2].toUint());
        }

        (
            uint256 msgNonce,
            address sender,
            address receiver,
            uint256 gasLimit,
            bytes memory data
        ) = abi.decode(message, (uint256, address, address, uint256, bytes));

        {
            // slot of sentMessages[msgNonce] = keccak256(keccak256(msgNonce . 0))
            bytes32 slotKey = keccak256(abi.encode(keccak256(abi.encode(msgNonce, 0))));
            bytes memory slotValue = MPT.verifyMPTProof(vars.storageRoot, slotKey, storageProof);
            require(bytes32(slotValue.toRlpItem().toUint()) == vars.msgHash, "TrustlessAMB: invalid message hash");
        }

        {
            require(messageId == bytes32(0), "TrustlessAMB: different message execution in progress");
            messageId = vars.msgHash;
            messageSender = sender;
            // ensure enough gas for the call + 3 SSTORE + event
            require((gasleft() * 63) / 64 > gasLimit + 40000, "TrustlessAMB: insufficient gas");
            (status,) = receiver.call{gas: gasLimit}(data);
            messageId = bytes32(0);
            messageSender = address(0);
        }
        executionStatus[vars.msgHash] = status ? ExecutionStatus.EXECUTION_SUCCEEDED : ExecutionStatus.EXECUTION_FAILED;
        emit ExecutedMessage(vars.msgHash, msgNonce, message, status);
    }

    function executeMessageFromLog(
        uint256 sourceBlock,
        uint256 txIndex,
        uint256 logIndex,
        bytes calldata message,
        bytes[] calldata receiptProof
    ) external returns (bool status) {
        bytes32 msgHash = keccak256(message);
        require(executionStatus[msgHash] == ExecutionStatus.NOT_EXECUTED, "TrustlessAMB: message already executed");

        bytes32 receiptsRoot = chain.receiptsRoot(sourceBlock);
        require(receiptsRoot != bytes32(0), "TrustlessAMB: stateRoot is missing");

        {
            bytes32 key = rlpIndex(txIndex);
            bytes memory receiptRLP = MPT.verifyMPTProof(receiptsRoot, key, receiptProof);
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
            require(messageId == bytes32(0), "TrustlessAMB: different message execution in progress");
            messageId = msgHash;
            messageSender = sender;
            // ensure enough gas for the call + 3 SSTORE + event
            require((gasleft() * 63) / 64 > gasLimit + 40000, "TrustlessAMB: insufficient gas");
            (status,) = receiver.call{gas: gasLimit}(data);
            messageId = bytes32(0);
            messageSender = address(0);
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
        return chain.head();
    }

    function messageCallStatus(bytes32 _messageId) external view returns (bool) {
        return executionStatus[_messageId] == ExecutionStatus.EXECUTION_SUCCEEDED;
    }
}
