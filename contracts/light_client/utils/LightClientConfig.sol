pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

contract LightClientConfig {
    uint256 public constant SLOTS_PER_EPOCH = 32;
    uint256 public constant SLOTS_PER_SYNC_COMMITTEE_PERIOD = 256 * SLOTS_PER_EPOCH;
    uint256 public constant SECONDS_PER_SLOT = 3;
    uint256 public constant MIN_SYNC_COMMITTEE_PARTICIPANTS = 10;
    uint256 public constant SYNC_COMMITTEE_SIZE = 512;

    uint256 internal constant SYNC_COMMITTEE_BIT_LIST_WORDS_SIZE = 2;
    uint256 internal constant SYNC_COMMITTEE_BRANCH_SIZE = 10;

    // get_generalized_index(BeaconState, 'finalized_checkpoint', 'root')
    uint256 internal constant FINALIZED_ROOT_INDEX = 105;
    // get_generalized_index(BeaconState, 'current_sync_committee')
    uint256 internal constant CURRENT_SYNC_COMMITTEE_INDEX = 54;
    // get_generalized_index(BeaconState, 'next_sync_committee')
    uint256 internal constant NEXT_SYNC_COMMITTEE_INDEX = 55;
    // get_generalized_index(BeaconState, 'latest_execution_payload_header')
    uint256 internal constant EXECUTION_PAYLOAD_INDEX = 56;
    // get_generalized_index(ExecutionPayloadHeader, 'state_root')
    uint256 internal constant EXECUTION_PAYLOAD_STATE_ROOT_INDEX = 18;
    // get_generalized_index(ExecutionPayloadHeader, 'block_number')
    uint256 internal constant EXECUTION_PAYLOAD_BLOCK_NUMBER_INDEX = 22;
}
