pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

import "./interfaces/IBeaconLightClient.sol";
import "./utils/CryptoUtils.sol";

contract LightClient is CryptoUtils {
    bytes32 public immutable GENESIS_VALIDATORS_ROOT;
    uint256 public immutable GENESIS_TIME;
    uint256 public immutable UPDATE_TIMEOUT;

    IBeaconLightClient.HeadPointer public head; // slot of latest known block + associated execution block number
    mapping(uint256 => IBeaconLightClient.StorageBeaconBlockHeader) public headers; // slot => header

    IBeaconLightClient.BestValidUpdate public bestValidUpdate;

    struct BeaconBlockHeader {
        uint64 slot;
        uint64 proposerIndex;
        bytes32 parentRoot;
        bytes32 stateRoot;
        bytes32 bodyRoot;
        uint64 executionBlockNumber;
        bytes32 executionStateRoot;
    }

    struct LightClientUpdate {
        // fork_version from the spec
        bytes4 forkVersion;

        // attested_header from the spec
        BeaconBlockHeader attestedHeader;

        // finalized_header from the spec
        // retrieved from the attested header, under FINALIZED_ROOT_INDEX index
        BeaconBlockHeader finalizedHeader;
        // finality_branch from the spec
        bytes32[] finalityBranch;

        // sync_aggregate from the spec
        // aggregated signature of attested header root
        G2Point syncAggregateSignature;
        bytes32[SYNC_COMMITTEE_BIT_LIST_WORDS_SIZE] syncAggregateBitList;

        // sync committee participants for signing attestedHeader, either a current_sync_committee or next_sync_committee from
        // from the latest proven header
        G1Point[SYNC_COMMITTEE_SIZE] syncCommittee;
        // aggregated PK of all syncCommittee keys, just for gas optimizations
        G1Point syncCommitteeAggregated;
        // validity merkle proof of current_sync_committee/next_sync_committee against the current known header
        bytes32[] syncCommitteeBranch;

        // validity merkle proof of execution payload root against the beacon state root
        bytes32[] executionPayloadBranch;
        // validity merkle proof of execution payload state root against execution payload root
        bytes32[] executionStateRootBranch;
        // validity merkle proof of execution payload block number against execution payload root
        bytes32[] executionBlockNumberBranch;
    }

    event HeadUpdated(uint256 indexed slot, bytes32 indexed root);
    event CandidateUpdated(uint256 indexed slot, bytes32 indexed root, uint256 signatures);

    constructor (
        bytes32 genesisValidatorsRoot,
        uint256 genesisTime,
        uint256 updateTimeout,
        BeaconBlockHeader memory startHeader
    ) {
        GENESIS_VALIDATORS_ROOT = genesisValidatorsRoot;
        GENESIS_TIME = genesisTime;
        UPDATE_TIMEOUT = updateTimeout;
        _setHead(
            IBeaconLightClient.HeadPointer(startHeader.slot, startHeader.executionBlockNumber),
            IBeaconLightClient.StorageBeaconBlockHeader(_headerRoot(startHeader), startHeader.stateRoot, startHeader.executionStateRoot)
        );
    }

    function executionStateRootByBlockNumber(uint256 blockNumber) external view returns (bytes32) {
        return headers[blockNumber].executionStateRoot;
    }

    function step(LightClientUpdate memory update) external {
        bool hasFinalityProof = update.finalityBranch.length > 0;
        BeaconBlockHeader memory activeHeader;
        if (hasFinalityProof) {
            activeHeader = update.finalizedHeader;
        } else {
            activeHeader = update.attestedHeader;
        }

        require(activeHeader.slot > head.slot, "Update slot is less or equal than current head");
        require(activeHeader.slot <= _curSlot(), "Update slot is too far in the future");

        uint256 syncCommitteeIndex;
        {
            uint256 currentSyncCommitteePeriod = _syncCommitteePeriod(head.slot);
            uint256 updateSyncCommitteePeriod = _syncCommitteePeriod(update.attestedHeader.slot);
            if (updateSyncCommitteePeriod == currentSyncCommitteePeriod) {
                syncCommitteeIndex = CURRENT_SYNC_COMMITTEE_INDEX;
            } else if (updateSyncCommitteePeriod == currentSyncCommitteePeriod + 1) {
                syncCommitteeIndex = NEXT_SYNC_COMMITTEE_INDEX;
            } else {
                revert("Signed slot is too far in the future");
            }
        }

        // verify that finality proof is correct
        bytes32 activeRoot = _headerRoot(activeHeader);
        bytes32 attestedRoot;
        bytes32 restoredStateRoot;
        if (hasFinalityProof) {
            attestedRoot = _headerRoot(update.attestedHeader);
            restoredStateRoot = _restoreMerkleRoot(activeRoot, FINALIZED_ROOT_INDEX, update.finalityBranch);
            require(update.attestedHeader.stateRoot == restoredStateRoot, "Cannot verify finality checkpoint proof");
        } else {
            attestedRoot = activeRoot;
            require(update.finalizedHeader.slot == 0, "Invalid finalizedHeader");
        }

        // verify that given execution state root & block number are correct
        bytes32 root = _uintToLE(activeHeader.executionBlockNumber);
        root = _restoreMerkleRoot(root, EXECUTION_PAYLOAD_BLOCK_NUMBER_INDEX, update.executionBlockNumberBranch);
        restoredStateRoot = _restoreMerkleRoot(activeHeader.executionStateRoot, EXECUTION_PAYLOAD_STATE_ROOT_INDEX, update.executionStateRootBranch);
        require(root == restoredStateRoot, "Cannot verify execution payload header proofs");

        // verify that given execution payload header root is correct
        restoredStateRoot = _restoreMerkleRoot(restoredStateRoot, EXECUTION_PAYLOAD_INDEX, update.executionPayloadBranch);
        require(restoredStateRoot == activeHeader.stateRoot, "Cannot verify execution state root proof");

        // verify that given sync committee is in the latest known block
        bytes32 syncCommitteeRoot = _hashSyncCommittee(update.syncCommittee, update.syncCommitteeAggregated);
        restoredStateRoot = _restoreMerkleRoot(syncCommitteeRoot, syncCommitteeIndex, update.syncCommitteeBranch);
        require(headers[head.slot].stateRoot == restoredStateRoot, "Cannot verify sync committee proof");

        // verify sync committee signature
        (uint256 count, G1Point memory aggregatedPK) = _aggregatePubkeys(update.syncCommittee, update.syncAggregateBitList);
        require(count >= MIN_SYNC_COMMITTEE_PARTICIPANTS, "Not enough signatures");
        bytes32 domainRoot = _syncDomainRoot(update.forkVersion);
        bytes32 signRoot = sha256(abi.encodePacked(attestedRoot, domainRoot));
        require(verifyBLSSignature(signRoot, aggregatedPK, update.syncAggregateSignature), "Invalid signature");

        IBeaconLightClient.HeadPointer memory newHead = IBeaconLightClient.HeadPointer(
            activeHeader.slot,
            activeHeader.executionBlockNumber
        );
        IBeaconLightClient.StorageBeaconBlockHeader memory compactHeader = IBeaconLightClient.StorageBeaconBlockHeader(
            activeRoot,
            activeHeader.stateRoot,
            activeHeader.executionStateRoot
        );
        if (3 * count >= 2 * SYNC_COMMITTEE_SIZE && hasFinalityProof) {
            _setHead(newHead, compactHeader);
        } else {
            if (bestValidUpdate.slot > head.slot) {
                // revert, if current candidate is valid and better than the proposed one
                require(count > bestValidUpdate.signatures, "Not a best candidate update");
            }
            _setCandidate(newHead, compactHeader, count);
        }
    }

    function applyCandidate() external {
        uint64 slot = bestValidUpdate.slot;
        IBeaconLightClient.StorageBeaconBlockHeader memory _header = IBeaconLightClient.StorageBeaconBlockHeader(
            bestValidUpdate.root,
            bestValidUpdate.stateRoot,
            bestValidUpdate.executionStateRoot
        );
        require(slot > head.slot, "No candidate update");
        require(_header.root != bytes32(0), "Invalid candidate update");
        require(_curSlot() > slot + SLOTS_PER_SYNC_COMMITTEE_PERIOD, "Waiting for sync period to end");
        require(bestValidUpdate.timeout < block.timestamp, "Waiting for UPDATE_TIMEOUT");

        _setHead(IBeaconLightClient.HeadPointer(slot, bestValidUpdate.executionBlockNumber), _header);
    }

    function _setHead(IBeaconLightClient.HeadPointer memory _head, IBeaconLightClient.StorageBeaconBlockHeader memory _header) internal {
        head = _head;
        headers[_head.slot] = _header;
        emit HeadUpdated(_head.slot, _header.root);
    }

    function _setCandidate(IBeaconLightClient.HeadPointer memory _head, IBeaconLightClient.StorageBeaconBlockHeader memory _header, uint256 _signatures) internal {
        bestValidUpdate = IBeaconLightClient.BestValidUpdate(
            _head.slot,
            _head.executionBlockNumber,
            uint64(_signatures),
            uint64(block.timestamp + UPDATE_TIMEOUT),
            _header.root,
            _header.stateRoot,
            _header.executionStateRoot
        );
        emit CandidateUpdated(_head.slot, _header.root, _signatures);
    }

    function _curSlot() internal returns (uint256) {
        return (block.timestamp - GENESIS_TIME) / SECONDS_PER_SLOT;
    }

    function _syncCommitteePeriod(uint256 _slot) internal returns (uint256) {
        return _slot / SLOTS_PER_SYNC_COMMITTEE_PERIOD;
    }

    function _syncDomainRoot(bytes4 _forkVersion) internal view returns (bytes32) {
        bytes32 syncDomainRoot = sha256(abi.encode(_forkVersion, GENESIS_VALIDATORS_ROOT));
        return (syncDomainRoot >> 32) | bytes32(uint256(0x07 << 248));
    }

    function _headerRoot(BeaconBlockHeader memory _header) internal view returns (bytes32) {
        return sha256(abi.encodePacked(
                sha256(abi.encodePacked(
                    sha256(abi.encodePacked(
                        _uintToLE(_header.slot),
                        _uintToLE(_header.proposerIndex)
                    )),
                    sha256(abi.encodePacked(
                        _header.parentRoot,
                        _header.stateRoot
                    ))
                )),
                sha256(abi.encodePacked(
                    sha256(abi.encodePacked(
                        _header.bodyRoot,
                        uint256(0)
                    )),
                    bytes32(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b) // sha256(abi.encodePacked(uint256(0), uint256(0)))
                ))
            ));
    }
}
