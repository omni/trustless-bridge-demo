pragma solidity 0.8.14;

interface IAMBCallReceiver {
    function onAMBMessageExecution(
        bytes32 messageId,
        address sender,
        bytes memory data
    ) external;
}
