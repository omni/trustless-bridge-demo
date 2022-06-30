package lightclient

import (
	"errors"
	"fmt"
	"log"
	"strconv"
	"time"

	"bls-sandbox/client"
	"bls-sandbox/config"
	"bls-sandbox/crypto"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	blscommon "github.com/prysmaticlabs/prysm/crypto/bls/common"
	ethpb2 "github.com/prysmaticlabs/prysm/proto/prysm/v1alpha1"
)

type LightClient struct {
	Client       client.Eth2Client
	Spec         *config.SpecConfig
	Genesis      *config.GenesisConfig
	WithFinality bool
}

func NewLightClient(cfg config.Eth2Config, finality bool) (*LightClient, error) {
	lc := &LightClient{
		Client:       client.NewClient(cfg.Client.URL),
		Spec:         cfg.Spec,
		Genesis:      cfg.Genesis,
		WithFinality: finality,
	}
	if cfg.Spec == nil {
		log.Println("Fetching chain spec")
		spec, err := lc.Client.GetSpec()
		if err != nil {
			return nil, fmt.Errorf("can't initialize light client: %w", err)
		}
		lc.Spec = &config.SpecConfig{
			SecondsPerSlot:               spec.SecondsPerSlot,
			SlotsPerEpoch:                spec.SlotsPerEpoch,
			AltairForkEpoch:              spec.AltairForkEpoch,
			AltairForkVersion:            spec.AltairForkVersion,
			BellatrixForkEpoch:           spec.BellatrixForkEpoch,
			BellatrixForkVersion:         spec.BellatrixForkVersion,
			EpochsPerSyncCommitteePeriod: spec.EpochsPerSyncCommitteePeriod,
			SyncCommitteeSize:            spec.SyncCommitteeSize,
			ValidatorRegistryLimit:       spec.ValidatorRegistryLimit,
			HistoricalRootsLimit:         spec.HistoricalRootsLimit,
			EpochsPerEth1VotingPeriod:    spec.EpochsPerEth1VotingPeriod,
			SlotsPerHistoricalRoot:       spec.SlotsPerHistoricalRoot,
		}
	}
	if cfg.Genesis == nil {
		log.Println("Fetching chain genesis info")
		genesis, err := lc.Client.GetGenesis()
		if err != nil {
			return nil, fmt.Errorf("can't initialize light client: %w", err)
		}
		seconds, err := strconv.ParseInt(genesis.GenesisTime, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("can't parse genesis time: %w", err)
		}
		lc.Genesis = &config.GenesisConfig{
			GenesisTime:           time.Unix(seconds, 0),
			GenesisValidatorsRoot: common.HexToHash(genesis.GenesisValidatorsRoot),
		}
	}
	return lc, nil
}

func (c *LightClient) MakeUpdate(curSlot uint64, targetSlot uint64) (*Update, error) {
	slotsPerPeriod := c.Spec.EpochsPerSyncCommitteePeriod * c.Spec.SlotsPerEpoch
	curPeriodStart := curSlot - curSlot%slotsPerPeriod
	nextPeriodEnd := curPeriodStart + 2*slotsPerPeriod - 1

	clockSlot := uint64(time.Since(c.Genesis.GenesisTime).Seconds()) / c.Spec.SecondsPerSlot
	slot := nextPeriodEnd
	if clockSlot < nextPeriodEnd {
		slot = clockSlot
	}
	if targetSlot > 0 {
		if targetSlot < curSlot {
			return nil, fmt.Errorf("target slot is behind current slot, %d < %d", targetSlot, curSlot)
		}
		slot = targetSlot
		if slot > nextPeriodEnd {
			return nil, fmt.Errorf("target slot is too far in the future, should be <= %d, got %d", nextPeriodEnd, targetSlot)
		}
	}
	curPeriod := curSlot / slotsPerPeriod

	var head *ethpb2.BeaconBlockBellatrix
	var err error

	for {
		log.Println("Fetching block for slot", slot)
		head, err = c.Client.GetBlock(slot)
		if err != nil {
			if errors.Is(err, client.NotFoundError) {
				slot--
				log.Println("Block does not exist, trying previous slot", slot)
				continue
			}
			return nil, fmt.Errorf("can't get block %d: %w", slot, err)
		}
		syncParticipants := head.Body.SyncAggregate.SyncCommitteeBits.Count()
		if syncParticipants < 10 || (c.WithFinality && syncParticipants < 512*2/3) {
			slot--
			log.Println("Not enough sync committee signatures", slot)
			continue
		}
		log.Printf("Chosen header with %d (%.2f%%) sync participants\n", syncParticipants, float64(syncParticipants)/5.12)
		break
	}

	attestedSlot := slot - 1
	var attestedBlock *ethpb2.BeaconBlockBellatrix
	for {
		log.Println("Fetching header for slot", attestedSlot)
		attestedBlock, err = c.Client.GetBlock(attestedSlot)
		if err != nil {
			if errors.Is(err, client.NotFoundError) {
				attestedSlot--
				log.Println("Header does not exist, trying previous slot", attestedSlot)
				continue
			}
			return nil, fmt.Errorf("can't get block %d: %w", attestedSlot, err)
		}
		break
	}

	curBlock, err := c.Client.GetBlock(curSlot)
	if err != nil {
		return nil, fmt.Errorf("can't get block %d: %w", curSlot, err)
	}

	headHeader := ConvertToHeader(head)
	attestedHeader := ConvertToHeader(attestedBlock)
	curHeader := ConvertToHeader(curBlock)
	attestedRoot := MustHashTreeRoot(attestedBlock)

	candidatePeriod := attestedSlot / slotsPerPeriod

	if headHeader.ParentRoot != attestedRoot {
		return nil, fmt.Errorf("block.parent_root != parent.root, %q != %q", headHeader.ParentRoot, attestedRoot)
	}

	log.Println("Fetching and proving sync committee", curSlot, attestedSlot)
	// check that obtained sync committee is reflected in the current block state_root
	cmt, proof, err := c.proveNewSyncCommittee(curSlot, curHeader.StateRoot, curPeriod != candidatePeriod)
	if err != nil {
		return nil, fmt.Errorf("can't prove sync committee: %w", err)
	}

	var pk blscommon.PublicKey
	for _, i := range head.Body.SyncAggregate.SyncCommitteeBits.BitIndices() {
		if pk == nil {
			pk = cmt.PublicKeys[i].Copy()
		} else {
			pk.Aggregate(cmt.PublicKeys[i])
		}
	}
	log.Println("Aggregate public key", hexutil.Encode(pk.Marshal()))
	log.Println("Checking sync committee aggregate signature", hexutil.Encode(pk.Marshal()))
	log.Println("Checking sync domain root", c.syncDomainRoot())
	// check that already known and proven sync committee signed some block header
	sig := crypto.MustDecodeSig(head.Body.SyncAggregate.SyncCommitteeSignature)
	if !crypto.Verify(attestedRoot, c.syncDomainRoot(), pk, sig) {
		return nil, fmt.Errorf("can't verify aggregate signature from sync committee")
	}

	forkVersion := [4]byte{}
	copy(forkVersion[:], common.FromHex(c.Spec.BellatrixForkVersion))
	update := &Update{
		ForkVersion:             forkVersion,
		AttestedHeader:          attestedHeader,
		SyncCommitteeAggregated: PkToG1(pk),
		SyncAggregateSignature:  SigToG2(sig),
		SyncCommitteeBranch:     proof.Path,
		FinalityBranch:          []common.Hash{},
	}
	state, stateTree, err := c.getBeaconState(attestedSlot, attestedHeader.StateRoot)
	if err != nil {
		return nil, fmt.Errorf("can't get finality beacon state: %w", err)
	}
	if c.WithFinality {
		finalizedBlock, err := c.Client.GetBlockByHash(common.BytesToHash(state.FinalizedCheckpoint.Root))
		if err != nil {
			return nil, fmt.Errorf("can't get finality block: %w", err)
		}
		update.FinalizedHeader = ConvertToHeader(finalizedBlock)
		update.FinalityBranch = append(
			[]common.Hash{crypto.UintToHash(uint64(state.FinalizedCheckpoint.Epoch))},
			stateTree.MakeProof(20).Path...,
		)

		if update.FinalizedHeader.Slot <= curSlot {
			return nil, nil
		}

		state, stateTree, err = c.getBeaconState(update.FinalizedHeader.Slot, update.FinalizedHeader.StateRoot)
		if err != nil {
			return nil, fmt.Errorf("can't get finality beacon state: %w", err)
		}
	} else {
		if attestedHeader.Slot <= curSlot {
			return nil, nil
		}
	}
	for _, pk := range cmt.PublicKeys {
		update.SyncCommittee = append(update.SyncCommittee, PkToG1(pk))
	}

	bits := head.Body.SyncAggregate.SyncCommitteeBits.Bytes()
	for w := 0; w < c.Spec.SyncCommitteeSize/256; w++ {
		for k := 0; k < 16; k++ {
			bits[w*32+k], bits[w*32+31-k] = bits[w*32+31-k], bits[w*32+k]
		}
	}
	for k := 0; k < c.Spec.SyncCommitteeSize/256; k++ {
		update.SyncAggregateBitList = append(update.SyncAggregateBitList, common.BytesToHash(bits[k*32:k*32+32]))
	}
	return update, nil
}

func (c *LightClient) getBeaconState(slot uint64, stateRoot common.Hash) (*ethpb2.BeaconStateBellatrix, *crypto.MerkleTree, error) {
	log.Println("Fetching full beacon state for slot", slot)
	state, err := c.Client.GetState(slot)
	if err != nil {
		return nil, nil, err
	}

	log.Println("Reconstructing beacon state merkle tree")
	stateTree := crypto.NewVectorMerkleTree(
		crypto.UintToHash(state.GenesisTime),
		common.BytesToHash(state.GenesisValidatorsRoot),
		crypto.UintToHash(uint64(state.Slot)),
		MustHashTreeRoot(state.Fork),
		MustHashTreeRoot(state.LatestBlockHeader),
		hashRootsVector(state.BlockRoots),
		hashRootsVector(state.StateRoots),
		hashRootsList(state.HistoricalRoots, c.Spec.HistoricalRootsLimit),
		MustHashTreeRoot(state.Eth1Data),
		hashEth1Datas(state.Eth1DataVotes, int(c.Spec.SlotsPerEpoch*c.Spec.EpochsPerEth1VotingPeriod)),
		crypto.UintToHash(state.Eth1DepositIndex),
		hashValidators(state.Validators, c.Spec.ValidatorRegistryLimit),
		hashUint64List(state.Balances, c.Spec.ValidatorRegistryLimit),
		hashRootsVector(state.RandaoMixes),
		hashUint64Vector(state.Slashings),
		hashUint8List(state.PreviousEpochParticipation, c.Spec.ValidatorRegistryLimit),
		hashUint8List(state.CurrentEpochParticipation, c.Spec.ValidatorRegistryLimit),
		crypto.BytesToMerkleHash(state.JustificationBits.Bytes()),
		MustHashTreeRoot(state.PreviousJustifiedCheckpoint),
		MustHashTreeRoot(state.CurrentJustifiedCheckpoint),
		MustHashTreeRoot(state.FinalizedCheckpoint),
		hashUint64List(state.InactivityScores, c.Spec.ValidatorRegistryLimit),
		MustHashTreeRoot(state.CurrentSyncCommittee),
		MustHashTreeRoot(state.NextSyncCommittee),
		MustHashTreeRoot(state.LatestExecutionPayloadHeader),
	)
	recStateRoot := stateTree.Hash()
	if recStateRoot != stateRoot {
		return nil, nil, fmt.Errorf("failed to reconstruct given state root, %s != %s", recStateRoot, stateRoot)
	}
	return state, stateTree, nil
}

func (c *LightClient) proveNewSyncCommittee(slot uint64, stateRoot common.Hash, next bool) (*SyncCommittee, *crypto.MerkleProof, error) {
	state, stateTree, err := c.getBeaconState(slot, stateRoot)
	if err != nil {
		return nil, nil, fmt.Errorf("Can't get beacon state: %w", err)
	}
	index := 22
	cmt := state.CurrentSyncCommittee
	if next {
		log.Println("Constructing a merkle proof for next_sync_committee generalized index")
		index = 23
		cmt = state.NextSyncCommittee
	}
	proof := stateTree.MakeProof(index)
	if proof.ReconstructRoot(MustHashTreeRoot(cmt)) != stateRoot {
		return nil, nil, fmt.Errorf("failed to verify merkle proof against state_root")
	}
	log.Println("Current sync committee is verified against given state root")
	return ConvertToSyncCommittee(cmt), proof, nil
}

func (c *LightClient) syncDomainRoot() common.Hash {
	res := common.Hash{7, 0, 0, 0}
	forkVersion := crypto.HexToMerkleHash(c.Spec.BellatrixForkVersion)
	forkRoot := crypto.Sha256Hash(forkVersion.Bytes(), c.Genesis.GenesisValidatorsRoot.Bytes())
	copy(res[4:], forkRoot[:28])
	return res
}
