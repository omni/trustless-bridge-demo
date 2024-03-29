package lightclient

import (
	"errors"
	"fmt"
	"log"
	"strconv"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/prysmaticlabs/prysm/encoding/bytesutil"
	ethpb2 "github.com/prysmaticlabs/prysm/proto/prysm/v1alpha1"

	"oracle/beaconclient"
	"oracle/config"
	"oracle/crypto"
)

const (
	MinSyncCommitteeParticipants = 10
)

type LightClient struct {
	Client       beaconclient.Eth2Client
	Spec         *config.SpecConfig
	Genesis      *config.GenesisConfig
	WithFinality bool
}

func NewLightClient(cfg config.Eth2Config, finality bool) (*LightClient, error) {
	lc := &LightClient{
		Client:       beaconclient.NewClient(cfg.Client.URL),
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

	var head *ethpb2.BeaconBlockBellatrix
	var err error

	for {
		log.Println("Fetching block for slot", slot)
		head, err = c.Client.GetBlock(strconv.FormatUint(slot, 10))
		if err != nil {
			if errors.Is(err, beaconclient.NotFoundError) {
				slot--
				log.Println("Block does not exist, trying previous slot", slot)
				continue
			}
			return nil, fmt.Errorf("can't get block %d: %w", slot, err)
		}
		syncParticipants := head.Body.SyncAggregate.SyncCommitteeBits.Count()
		if syncParticipants < MinSyncCommitteeParticipants || (c.WithFinality && 3*syncParticipants < 2*uint64(c.Spec.SyncCommitteeSize)) {
			slot--
			log.Println("Not enough sync committee signatures", slot)
			continue
		}
		participation := float64(syncParticipants) * 100 / float64(c.Spec.SyncCommitteeSize)
		log.Printf("Chosen header with %d (%.2f%%) sync participants\n", syncParticipants, participation)
		break
	}

	signatureSlot := uint64(head.Slot)
	attestedRoot := common.BytesToHash(head.ParentRoot)
	log.Println("Fetching block for root ", attestedRoot)
	attestedBlock, err := c.Client.GetBlock(attestedRoot.String())
	if err != nil {
		return nil, fmt.Errorf("can't get block %s: %w", attestedRoot, err)
	}
	attestedHeader := ConvertToHeader(attestedBlock)

	curBlock, err := c.Client.GetBlock(strconv.FormatUint(curSlot, 10))
	if err != nil {
		return nil, fmt.Errorf("can't get block %d: %w", curSlot, err)
	}

	log.Println("Fetching and proving sync committee", curSlot, signatureSlot)
	isNext := curSlot/slotsPerPeriod != curSlot/slotsPerPeriod
	// check that obtained sync committee is reflected in the current block state_root
	cmt, proof, err := c.proveNewSyncCommittee(curSlot, common.BytesToHash(curBlock.StateRoot), isNext)
	if err != nil {
		return nil, fmt.Errorf("can't prove sync committee: %w", err)
	}

	var pk *crypto.G1Point
	var missingPKs []crypto.G1PointCompressed
	var hashedPublicKeys []common.Hash
	var indices []int
	for i := 0; i < c.Spec.SyncCommitteeSize; i++ {
		hashedPublicKeys = append(hashedPublicKeys, crypto.HashG1PointCompressed(&cmt.PublicKeys[i]))
		if head.Body.SyncAggregate.SyncCommitteeBits.BitAt(uint64(i)) {
			pk = crypto.AddG1Points(pk, &cmt.PublicKeys[i])
		} else {
			indices = append(indices, i)
		}
	}
	for i := range indices {
		missingPKs = append(missingPKs, cmt.PublicKeys[indices[len(indices)-1-i]])
	}
	tree := crypto.NewVectorMerkleTree(hashedPublicKeys...)
	multiProof := tree.MakeMultiProof(indices)
	log.Printf("Verifying sync committee signature, aggregated pk = %s\n", pk.String())
	// check that already known and proven sync committee signed some block header
	sig := crypto.MustDecodeSig(head.Body.SyncAggregate.SyncCommitteeSignature)
	if !crypto.Verify(attestedRoot, c.syncDomainRoot(), *pk, sig) {
		return nil, fmt.Errorf("can't verify aggregate signature from sync committee")
	}

	forkVersion := [4]byte{}
	copy(forkVersion[:], common.FromHex(c.Spec.BellatrixForkVersion))
	update := &Update{
		ForkVersion:                     forkVersion,
		SignatureSlot:                   uint64(head.Slot),
		AttestedHeader:                  attestedHeader,
		SyncAggregatePubkey:             *pk,
		SyncAggregateSignature:          sig,
		SyncCommitteeBranch:             proof.Path,
		FinalityBranch:                  []common.Hash{},
		MissedSyncCommitteeParticipants: missingPKs,
		SyncCommitteeRootDecommitments:  multiProof.Decommitments,
	}
	if c.WithFinality {
		log.Println("Fetching full beacon state for slot", attestedHeader.Slot)
		state, stateTree, err := c.GetBeaconState(attestedHeader.Slot)
		if err != nil {
			return nil, fmt.Errorf("can't get finality beacon state: %w", err)
		}
		recStateRoot := stateTree.Hash()
		if recStateRoot != attestedHeader.StateRoot {
			log.Fatalf("failed to reconstruct given state root, %s != %s\n", recStateRoot, attestedHeader.StateRoot)
		}
		finalizedBlock, err := c.Client.GetBlock(hexutil.Encode(state.FinalizedCheckpoint.Root))
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
	} else {
		if attestedHeader.Slot <= curSlot {
			return nil, nil
		}
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

func (c *LightClient) GetBeaconState(slot uint64) (*ethpb2.BeaconStateBellatrix, *crypto.MerkleTree, error) {
	state, err := c.Client.GetState(slot)
	if err != nil {
		return nil, nil, err
	}

	stateTree := crypto.NewVectorMerkleTree(
		crypto.UintToHash(state.GenesisTime),
		common.BytesToHash(state.GenesisValidatorsRoot),
		crypto.UintToHash(uint64(state.Slot)),
		crypto.MustHashTreeRoot(state.Fork),
		crypto.MustHashTreeRoot(state.LatestBlockHeader),
		crypto.HashRootsVector(state.BlockRoots),
		crypto.HashRootsVector(state.StateRoots),
		crypto.HashRootsList(state.HistoricalRoots, c.Spec.HistoricalRootsLimit),
		crypto.MustHashTreeRoot(state.Eth1Data),
		crypto.HashEth1Datas(state.Eth1DataVotes, int(c.Spec.SlotsPerEpoch*c.Spec.EpochsPerEth1VotingPeriod)),
		crypto.UintToHash(state.Eth1DepositIndex),
		crypto.HashValidators(state.Validators, c.Spec.ValidatorRegistryLimit),
		crypto.HashUint64List(state.Balances, c.Spec.ValidatorRegistryLimit),
		crypto.HashRootsVector(state.RandaoMixes),
		crypto.HashUint64Vector(state.Slashings),
		crypto.HashUint8List(state.PreviousEpochParticipation, c.Spec.ValidatorRegistryLimit),
		crypto.HashUint8List(state.CurrentEpochParticipation, c.Spec.ValidatorRegistryLimit),
		crypto.BytesToMerkleHash(state.JustificationBits.Bytes()),
		crypto.MustHashTreeRoot(state.PreviousJustifiedCheckpoint),
		crypto.MustHashTreeRoot(state.CurrentJustifiedCheckpoint),
		crypto.MustHashTreeRoot(state.FinalizedCheckpoint),
		crypto.HashUint64List(state.InactivityScores, c.Spec.ValidatorRegistryLimit),
		crypto.MustHashTreeRoot(state.CurrentSyncCommittee),
		crypto.MustHashTreeRoot(state.NextSyncCommittee),
		crypto.MustHashTreeRoot(state.LatestExecutionPayloadHeader),
	)
	return state, stateTree, nil
}

func (c *LightClient) MakeExecutionPayloadStateRootProof(slot uint64) ([]common.Hash, error) {
	state, stateTree, err := c.GetBeaconState(slot)
	if err != nil {
		return nil, fmt.Errorf("can't get beacon state: %w", err)
	}
	proof1 := stateTree.MakeProof(24)

	payloadTree := makeExecutionPayloadTree(state.LatestExecutionPayloadHeader)
	proof2 := payloadTree.MakeProof(2)

	return append(proof2.Path, proof1.Path...), nil
}

func (c *LightClient) MakeExecutionPayloadReceiptsRootProof(sourceSlot, targetSlot uint64) ([]common.Hash, error) {
	if sourceSlot < targetSlot {
		return nil, fmt.Errorf("can't make proof for sourceSlot %d < targetSlot %d", sourceSlot, targetSlot)
	}
	sourceState, sourceStateTree, err := c.GetBeaconState(sourceSlot)
	if err != nil {
		return nil, fmt.Errorf("can't get beacon state: %w", err)
	}
	targetState, targetStateTree, err := c.GetBeaconState(targetSlot)
	if err != nil {
		return nil, fmt.Errorf("can't get beacon state: %w", err)
	}

	var proof []common.Hash
	if sourceSlot == targetSlot {
		// do nothing
	} else if targetSlot+c.Spec.SlotsPerHistoricalRoot > sourceSlot {
		var hashes []common.Hash
		for _, h := range sourceState.StateRoots {
			hashes = append(hashes, common.BytesToHash(h))
		}
		proof1 := crypto.NewVectorMerkleTree(hashes...).MakeProof(int(targetSlot) % len(sourceState.StateRoots))
		proof2 := sourceStateTree.MakeProof(6)
		proof = append(proof1.Path, proof2.Path...)
	} else {
		historicalRootIndex := targetSlot / c.Spec.SlotsPerHistoricalRoot
		historicalBatchSlot := historicalRootIndex*c.Spec.SlotsPerHistoricalRoot + c.Spec.SlotsPerHistoricalRoot

		historicalState, _, err2 := c.GetBeaconState(historicalBatchSlot)
		if err2 != nil {
			return nil, fmt.Errorf("can't get beacon state: %w", err2)
		}

		// state_root -> state_roots -> historical_root -> historical_roots -> state_root
		var stateRoots, blockRoots, historicalRoots []common.Hash
		for i := range historicalState.StateRoots {
			stateRoots = append(stateRoots, common.BytesToHash(historicalState.StateRoots[i]))
			blockRoots = append(blockRoots, common.BytesToHash(historicalState.BlockRoots[i]))
		}
		for _, h := range sourceState.HistoricalRoots {
			historicalRoots = append(historicalRoots, common.BytesToHash(h))
		}
		proof1 := crypto.NewVectorMerkleTree(stateRoots...).MakeProof(int(targetSlot) % len(historicalState.StateRoots))
		proof2 := crypto.NewListMerkleTree(historicalRoots, c.Spec.HistoricalRootsLimit).MakeProof(int(historicalRootIndex))
		proof3 := sourceStateTree.MakeProof(7)

		proof = append(proof1.Path, crypto.NewVectorMerkleTree(blockRoots...).Hash())
		proof = append(proof, proof2.Path...)
		proof = append(proof, proof3.Path...)
	}

	payloadTree := makeExecutionPayloadTree(targetState.LatestExecutionPayloadHeader)
	proof = append(targetStateTree.MakeProof(24).Path, proof...)
	proof = append(payloadTree.MakeProof(3).Path, proof...)
	return proof, nil
}

func (c *LightClient) FindBeaconBlockByExecutionBlockNumber(blockNumber uint64) (uint64, error) {
	log.Printf("Looking for beacon block with execution payload block %d\n", blockNumber)
	block, err := c.Client.GetBlock("head")
	if err != nil {
		return 0, fmt.Errorf("can't get latest block: %w", err)
	}

	if block.Body.ExecutionPayload == nil {
		return 0, fmt.Errorf("latest beacon block at slot %d has empty execution payload", block.Slot)
	}
	latestExecutionBlock := block.Body.ExecutionPayload.BlockNumber
	if latestExecutionBlock < blockNumber {
		return 0, fmt.Errorf("latest execution block number %d is less than target block number %d", latestExecutionBlock, blockNumber)
	}
	l, r := c.Spec.BellatrixForkEpoch*c.Spec.SlotsPerEpoch, uint64(block.Slot)
	for l < r {
		m := (l + r) / 2
		for s := uint64(1); m >= l && m <= r; s++ {
			block, err = c.Client.GetBlock(strconv.FormatUint(m, 10))
			if err != nil {
				log.Printf("can't get beacon block at slot %d\n", m)
				if s%2 == 0 {
					m += s
				} else {
					m -= s
				}
				continue
			}
			break
		}
		if m < l || m > r {
			l = r
			break
		}
		if block.Body.ExecutionPayload == nil || block.Body.ExecutionPayload.BlockNumber < blockNumber {
			l = m + 1
		} else {
			r = m
		}
	}
	return l, nil
}

func (c *LightClient) proveNewSyncCommittee(slot uint64, stateRoot common.Hash, next bool) (*SyncCommittee, *crypto.MerkleProof, error) {
	state, stateTree, err := c.GetBeaconState(slot)
	if err != nil {
		return nil, nil, fmt.Errorf("can't get beacon state: %w", err)
	}
	index := 22
	cmt := state.CurrentSyncCommittee
	if next {
		log.Println("Constructing a merkle proof for next_sync_committee generalized index")
		index = 23
		cmt = state.NextSyncCommittee
	}
	proof := stateTree.MakeProof(index)
	if proof.ReconstructRoot(crypto.MustHashTreeRoot(cmt)) != stateRoot {
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

func makeExecutionPayloadTree(payload *ethpb2.ExecutionPayloadHeader) *crypto.MerkleTree {
	return crypto.NewVectorMerkleTree(
		common.BytesToHash(payload.ParentHash),
		common.BytesToHash(bytesutil.PadTo(payload.FeeRecipient, 32)),
		common.BytesToHash(payload.StateRoot),
		common.BytesToHash(payload.ReceiptsRoot),
		crypto.BytesToMerkleHash(payload.LogsBloom),
		common.BytesToHash(payload.PrevRandao),
		crypto.UintToHash(payload.BlockNumber),
		crypto.UintToHash(payload.GasLimit),
		crypto.UintToHash(payload.GasUsed),
		crypto.UintToHash(payload.Timestamp),
		crypto.HashUint8List(payload.ExtraData, 32),
		common.BytesToHash(payload.BaseFeePerGas),
		common.BytesToHash(payload.BlockHash),
		common.BytesToHash(payload.TransactionsRoot),
	)
}
