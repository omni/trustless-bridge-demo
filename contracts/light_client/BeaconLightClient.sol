pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

import "./interfaces/IBeaconLightClient.sol";
import "./libraries/LittleEndian.sol";
import "./libraries/Merkle.sol";
import "./utils/BeaconLightClientCryptoUtils.sol";

contract BeaconLightClient is BeaconLightClientCryptoUtils {
    bytes32 public immutable GENESIS_VALIDATORS_ROOT;
    uint256 public immutable GENESIS_TIME;
    uint256 public immutable UPDATE_TIMEOUT;

    uint256 public head; // slot of latest known block
    mapping(uint256 => IBeaconLightClient.StorageBeaconBlockHeader) public headers; // slot => header

    IBeaconLightClient.BestValidUpdate public bestValidUpdate;

    struct BeaconBlockHeader {
        uint64 slot;
        uint64 proposerIndex;
        bytes32 parentRoot;
        bytes32 stateRoot;
        bytes32 bodyRoot;
    }

    struct LightClientUpdate {
        // fork_version from the spec
        bytes4 forkVersion;

        // signature_slot from the spec
        uint64 signatureSlot;

        // attested_header from the spec
        BeaconBlockHeader attestedHeader;

        // finalized_header from the spec
        // retrieved from the attested header, under FINALIZED_ROOT_INDEX index
        BeaconBlockHeader finalizedHeader;
        // finality_branch from the spec
        bytes32[] finalityBranch;

        // sync_aggregate from the spec
        // aggregated signature of attested header root
        BLS12381.G2Point syncAggregateSignature;
        bytes32[SYNC_COMMITTEE_BIT_LIST_WORDS_SIZE] syncAggregateBitList;
        // aggregated PK of participating syncCommittee keys, as described by syncAggregateBitList
        BLS12381.G1Point syncAggregatePubkey;

        // sync committee participants for signing attestedHeader, either a current_sync_committee or next_sync_committee from
        // from the latest proven header
        BLS12381.G1PointCompressed[SYNC_COMMITTEE_SIZE] syncCommittee;
        // validity merkle proof of current_sync_committee/next_sync_committee against the current known header
        bytes32[] syncCommitteeBranch;
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
            startHeader.slot,
            IBeaconLightClient.StorageBeaconBlockHeader(_headerRoot(startHeader), startHeader.stateRoot)
        );
    }

    function stateRoot(uint256 slot) external view returns (bytes32) {
        return headers[slot].stateRoot;
    }

    function step(LightClientUpdate memory update) external {
        bool hasFinalityProof = update.finalityBranch.length > 0;
        BeaconBlockHeader memory activeHeader;
        if (hasFinalityProof) {
            activeHeader = update.finalizedHeader;
        } else {
            require(update.finalizedHeader.slot == 0, "Invalid finalizedHeader");
            activeHeader = update.attestedHeader;
        }

        require(activeHeader.slot > head, "Update slot is less or equal than current head");
        require(activeHeader.slot <= _curSlot(), "Update slot is too far in the future");

        uint256 syncCommitteeIndex;
        {
            uint256 currentSyncCommitteePeriod = _syncCommitteePeriod(head);
            uint256 updateSyncCommitteePeriod = _syncCommitteePeriod(update.signatureSlot);
            if (updateSyncCommitteePeriod == currentSyncCommitteePeriod) {
                syncCommitteeIndex = CURRENT_SYNC_COMMITTEE_INDEX;
            } else if (updateSyncCommitteePeriod == currentSyncCommitteePeriod + 1) {
                syncCommitteeIndex = NEXT_SYNC_COMMITTEE_INDEX;
            } else {
                revert("Signature slot is too far in the future");
            }
        }

        // verify that finality proof is correct
        bytes32 attestedRoot = _headerRoot(update.attestedHeader);
        bytes32 activeRoot = attestedRoot;
        if (hasFinalityProof) {
            activeRoot = _headerRoot(update.finalizedHeader);
            bytes32 restoredStateRoot = Merkle.restoreMerkleRoot(activeRoot, FINALIZED_ROOT_INDEX, update.finalityBranch);
            require(update.attestedHeader.stateRoot == restoredStateRoot, "Cannot verify finality checkpoint proof");
        }

        // aggregate sync committee pub keys
        (uint256 count, BLS12381.G1Point memory aggregatedPK) = _aggregateRemainingPubkeys(
            update.syncCommittee,
            update.syncAggregatePubkey,
            update.syncAggregateBitList
        );
        require(count >= MIN_SYNC_COMMITTEE_PARTICIPANTS, "Not enough signatures");

        // verify that given sync committee is in the latest known block
        bytes32 syncCommitteeRoot = _hashSyncCommittee(update.syncCommittee, aggregatedPK);
        bytes32 restoredStateRoot = Merkle.restoreMerkleRoot(syncCommitteeRoot, syncCommitteeIndex, update.syncCommitteeBranch);
        require(headers[head].stateRoot == restoredStateRoot, "Cannot verify sync committee proof");

        // verify sync committee signature
        bytes32 domainRoot = _syncDomainRoot(update.forkVersion);
        bytes32 signRoot = sha256(abi.encodePacked(attestedRoot, domainRoot));
        require(BLS12381.verifyBLSSignature(signRoot, update.syncAggregatePubkey, update.syncAggregateSignature), "Invalid signature");

        IBeaconLightClient.StorageBeaconBlockHeader memory compactHeader = IBeaconLightClient.StorageBeaconBlockHeader(
            activeRoot,
            activeHeader.stateRoot
        );
        if (3 * count >= 2 * SYNC_COMMITTEE_SIZE && hasFinalityProof) {
            _setHead(activeHeader.slot, compactHeader);
        } else {
            if (bestValidUpdate.slot > head) {
                // revert, if current candidate is valid and better than the proposed one
                require(count > bestValidUpdate.signatures, "Not a best candidate update");
            }
            _setCandidate(activeHeader.slot, compactHeader, count);
        }
    }

    function applyCandidate() external {
        uint64 slot = bestValidUpdate.slot;
        IBeaconLightClient.StorageBeaconBlockHeader memory _header = IBeaconLightClient.StorageBeaconBlockHeader(
            bestValidUpdate.root,
            bestValidUpdate.stateRoot
        );
        require(slot > head, "No candidate update");
        require(_header.root != bytes32(0), "Invalid candidate update");
        require(_curSlot() > slot + SLOTS_PER_SYNC_COMMITTEE_PERIOD, "Waiting for sync period to end");
        require(bestValidUpdate.timeout < block.timestamp, "Waiting for UPDATE_TIMEOUT");

        _setHead(slot, _header);
    }

    function _setHead(uint256 _head, IBeaconLightClient.StorageBeaconBlockHeader memory _header) internal {
        head = _head;
        headers[_head] = _header;
        emit HeadUpdated(_head, _header.root);
    }

    function _setCandidate(uint256 _head, IBeaconLightClient.StorageBeaconBlockHeader memory _header, uint256 _signatures) internal {
        bestValidUpdate = IBeaconLightClient.BestValidUpdate(
            uint64(_head),
            uint64(_signatures),
            uint64(block.timestamp + UPDATE_TIMEOUT),
            _header.root,
            _header.stateRoot
        );
        emit CandidateUpdated(_head, _header.root, _signatures);
    }

    function _curSlot() internal view returns (uint256) {
        return (block.timestamp - GENESIS_TIME) / SECONDS_PER_SLOT;
    }

    function _syncCommitteePeriod(uint256 _slot) internal view returns (uint256) {
        return _slot / SLOTS_PER_SYNC_COMMITTEE_PERIOD;
    }

    function _syncDomainRoot(bytes4 _forkVersion) internal view returns (bytes32) {
        bytes32 syncDomainRoot = sha256(abi.encode(_forkVersion, GENESIS_VALIDATORS_ROOT));
        return (syncDomainRoot >> 32) | bytes32(uint256(0x07 << 248));
    }

    function _headerRoot(BeaconBlockHeader memory _header) internal pure returns (bytes32) {
        return sha256(abi.encodePacked(
                sha256(abi.encodePacked(
                    sha256(abi.encodePacked(
                        LittleEndian.encode(_header.slot),
                        LittleEndian.encode(_header.proposerIndex)
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
