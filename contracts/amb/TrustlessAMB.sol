pragma solidity 0.8.14;

import "./libraries/MPT.sol";
import "./TrustlessAMBStorage.sol";
import "./proxy/EIP1967Admin.sol";
import "../light_client/LightClient.sol";

contract TrustlessAMB is TrustlessAMBStorage, EIP1967Admin {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    function initialize(address newLightClient, uint256 newMaxGasPerTx, address otherSideAMB) external {
        lightClient = IBeaconLightClient(newLightClient);
        maxGasPerTx = newMaxGasPerTx;
        otherSideImage = keccak256(abi.encodePacked(otherSideAMB));
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

        vars.stateRoot = lightClient.executionStateRootByBlockNumber(sourceBlock);

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

    function head() external view returns (IBeaconLightClient.HeadPointer memory) {
        return lightClient.head();
    }

    function messageCallStatus(bytes32 _messageId) external view returns (bool) {
        return executionStatus[_messageId] == ExecutionStatus.EXECUTION_SUCCEEDED;
    }
}
