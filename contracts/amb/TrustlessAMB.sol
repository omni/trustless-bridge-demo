pragma solidity 0.8.14;

import "./interfaces/IAMBCallReceiver.sol";
import "./interfaces/ITrustlessAMB.sol";
import "./utils/MPT.sol";
import "../light_client/LightClient.sol";

contract TrustlessAMB is ITrustlessAMB, MPT {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.Iterator;
    using RLPReader for bytes;

    mapping(uint256 => bytes32) public sentMessages;
    mapping(bytes32 => bool) public executedMessages;
    mapping(bytes32 => bool) public messageCallStatus;

    IBeaconLightClient public lightClient;

    address public otherSideTrustlessAMB;

    uint256 nonce;

    address public messageSender;
    bytes32 public messageId;
    uint256 public maxGasPerTx;

    address public owner;

    event SentMessage(bytes32 indexed msgHash, uint256 indexed nonce, bytes message);
    event ExecutedMessage(bytes32 indexed msgHash, uint256 indexed nonce, bytes message, bool status);

    constructor (address newLightClient) {
        owner = msg.sender;
        lightClient = IBeaconLightClient(newLightClient);
        maxGasPerTx = 2000000;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: not an owner");
        _;
    }

    function setOtherSideTrustlessAMB(address newOtherSideTrustlessAMB) external onlyOwner {
        otherSideTrustlessAMB = newOtherSideTrustlessAMB;
    }

    function requireToPassMessage(address receiver,
        bytes calldata data,
        uint256 gasLimit
    ) external returns (bytes32) {
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
        require(!executedMessages[vars.msgHash], "TrustlessAMB: message already executed");

        vars.stateRoot = lightClient.executionStateRootByBlockNumber(sourceBlock);

        require(vars.stateRoot != bytes32(0), "TrustlessAMB: stateRoot is missing");

        {
            bytes memory accountRLP = _verifyMPTProof(vars.stateRoot, keccak256(abi.encodePacked(otherSideTrustlessAMB)), accountProof);
            RLPReader.RLPItem[] memory ls = accountRLP.toRlpItem().toList();
            require(ls.length == 4, "TrustlessAMB: invalid account decoded from RLP");
            vars.storageRoot = bytes32(ls[2].toUint());
        }

        (uint256 msgNonce, address sender, address receiver, uint256 gasLimit, bytes memory data) = abi.decode(message, (uint256, address, address, uint256, bytes));

        {
            bytes32 slotKey = keccak256(abi.encode(keccak256(abi.encode(msgNonce, 0))));
            bytes memory slotValue = _verifyMPTProof(vars.storageRoot, slotKey, storageProof);
            require(bytes32(slotValue.toRlpItem().toUint()) == vars.msgHash, "TrustlessAMB: invalid message hash");
        }

        {
            bytes memory encodedData = abi.encodeWithSelector(IAMBCallReceiver.onAMBMessageExecution.selector, vars.msgHash, sender, data);
            messageId = vars.msgHash;
            messageSender = sender;
            require(gasleft() > gasLimit + 20000, "TrustlessAMB: insufficient gas");
            (status,) = receiver.call{gas: gasLimit}(data);
            messageId = bytes32(0);
            messageSender = address(0);
        }
        executedMessages[vars.msgHash] = true;
        messageCallStatus[vars.msgHash] = status;
        emit ExecutedMessage(vars.msgHash, msgNonce, message, status);
    }

    function head() external view returns (IBeaconLightClient.HeadPointer memory) {
        return lightClient.head();
    }
}
