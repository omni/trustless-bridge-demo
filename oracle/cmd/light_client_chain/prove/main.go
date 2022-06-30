package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"flag"
	"log"
	"math/big"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/prysmaticlabs/prysm/encoding/bytesutil"
	ethpb2 "github.com/prysmaticlabs/prysm/proto/prysm/v1alpha1"

	"bls-sandbox/config"
	"bls-sandbox/contract"
	"bls-sandbox/crypto"
	"bls-sandbox/lightclient"
	"bls-sandbox/sender"
)

var (
	sourceBeaconRPC     = flag.String("sourceBeaconRPC", "", "")
	targetRPC           = flag.String("targetRPC", "", "")
	lightClientContract = flag.String("lightClientContract", "", "")
	chainContract       = flag.String("chainContract", "", "")
	startSlot           = flag.Uint64("startSlot", 0, "")
	targetSlot          = flag.Uint64("targetSlot", 0, "")
	keystore            = flag.String("keystore", "", "")
	keystorePass        = flag.String("keystorePass", "", "")
)

func main() {
	flag.Parse()

	lc, err := lightclient.NewLightClient(config.Eth2Config{
		Client: config.HTTPClientConfig{
			URL: *sourceBeaconRPC,
		},
	}, true)
	if err != nil {
		log.Fatalln(err)
	}

	targetClient, err := ethclient.Dial(*targetRPC)
	if err != nil {
		log.Fatalln(err)
	}

	if *startSlot == 0 {
		headData, err2 := contract.BeaconLightClientABI.Pack("head")
		if err2 != nil {
			log.Fatalln(err2)
		}
		addr := common.HexToAddress(*lightClientContract)
		data, err2 := targetClient.CallContract(context.TODO(), ethereum.CallMsg{
			From: common.Address{},
			To:   &addr,
			Data: headData,
		}, nil)
		if err2 != nil {
			log.Fatalln(err2)
		}
		if len(data) != 32 {
			log.Fatalln("head() should return 32 bytes")
		}
		slot := binary.BigEndian.Uint64(data[24:32])
		startSlot = &slot

		log.Printf("using current head slot from light client contract %d\n", slot)
	}

	var data []byte
	if *targetSlot > *startSlot {
		log.Fatalf("targetSlot should be <= %d\n", *startSlot)
	}
	if *targetSlot == 0 || *targetSlot == *startSlot {
		log.Printf("calling verifyExecutionPayload for slot %d\n", *startSlot)
		state, stateTree := getState(lc, *startSlot)
		proof1 := stateTree.MakeProof(24)
		payload := NewExecutionPayload(state.LatestExecutionPayloadHeader)
		data, err = contract.LightClientChainABI.Pack(
			"verifyExecutionPayload",
			big.NewInt(int64(*startSlot)),
			big.NewInt(int64(*startSlot)),
			&payload,
			proof1.Path,
		)
		if err != nil {
			log.Fatalln(err)
		}
	} else if *targetSlot+lc.Spec.SlotsPerHistoricalRoot > *startSlot {
		log.Printf("calling verifyExecutionPayload for slots %d->%d\n", *startSlot, *targetSlot)
		state, stateTree := getState(lc, *startSlot)
		state2, stateTree2 := getState(lc, *targetSlot)
		proof1 := stateTree2.MakeProof(24)
		var hashes []common.Hash
		for _, h := range state.StateRoots {
			hashes = append(hashes, common.BytesToHash(h))
		}
		proof2 := crypto.NewVectorMerkleTree(hashes...).MakeProof(int(*targetSlot) % len(state.StateRoots))
		proof3 := stateTree.MakeProof(6)
		payload := NewExecutionPayload(state2.LatestExecutionPayloadHeader)
		proof := append(proof1.Path, proof2.Path...)
		proof = append(proof, proof3.Path...)
		data, err = contract.LightClientChainABI.Pack(
			"verifyExecutionPayload",
			big.NewInt(int64(*startSlot)),
			big.NewInt(int64(*targetSlot)),
			&payload,
			proof,
		)
		if err != nil {
			log.Fatalln(err)
		}
	} else {
		historicalRootIndex := *targetSlot / lc.Spec.SlotsPerHistoricalRoot
		historicalBatchSlot := historicalRootIndex*lc.Spec.SlotsPerHistoricalRoot + lc.Spec.SlotsPerHistoricalRoot
		log.Printf("calling verifyExecutionPayload for slots %d->%d->%d\n", *startSlot, historicalBatchSlot, *targetSlot)
		state, stateTree := getState(lc, *startSlot)
		state2, _ := getState(lc, historicalBatchSlot)
		state3, stateTree3 := getState(lc, *targetSlot)

		// execution_payload_root -> state_root -> state_roots -> historical_root -> historical_roots -> state_root
		proof1 := stateTree3.MakeProof(24)
		var stateRoots, blockRoots, historicalRoots []common.Hash
		for i := range state2.StateRoots {
			stateRoots = append(stateRoots, common.BytesToHash(state2.StateRoots[i]))
			blockRoots = append(blockRoots, common.BytesToHash(state2.BlockRoots[i]))
		}
		for _, h := range state.HistoricalRoots {
			historicalRoots = append(historicalRoots, common.BytesToHash(h))
		}
		proof2 := crypto.NewVectorMerkleTree(stateRoots...).MakeProof(int(*targetSlot) % len(state.StateRoots))
		proof3 := crypto.NewListMerkleTree(historicalRoots, lc.Spec.HistoricalRootsLimit).MakeProof(int(historicalRootIndex))
		proof4 := stateTree.MakeProof(7)

		payload := NewExecutionPayload(state3.LatestExecutionPayloadHeader)
		proof := append(proof1.Path, proof2.Path...)
		proof = append(proof, crypto.NewVectorMerkleTree(blockRoots...).Hash())
		proof = append(proof, proof3.Path...)
		proof = append(proof, proof4.Path...)

		data, err = contract.LightClientChainABI.Pack(
			"verifyExecutionPayload",
			big.NewInt(int64(*startSlot)),
			big.NewInt(int64(*targetSlot)),
			&payload,
			proof,
		)
		if err != nil {
			log.Fatalln(err)
		}
	}

	s, err := sender.NewTxSender(context.TODO(), targetClient, *keystore, *keystorePass)
	if err != nil {
		log.Fatalln(err)
	}

	to := common.HexToAddress(*chainContract)
	gas, err := targetClient.EstimateGas(context.TODO(), ethereum.CallMsg{
		To:   &to,
		Data: data,
	})
	if err != nil {
		log.Fatalln("estimate gas failed:", err)
	}
	log.Printf("Estimated gas: %d", gas)
	signedTx, err := s.SendTx(context.TODO(), &types.DynamicFeeTx{
		GasTipCap: big.NewInt(1e9),
		GasFeeCap: big.NewInt(1e9),
		Gas:       gas + gas/2,
		To:        &to,
		Data:      data,
	})
	if err != nil {
		log.Fatalln(err)
	}
	log.Printf("Sent tx: %s\n", signedTx.Hash())
	receipt, err := s.WaitReceipt(context.TODO(), signedTx)
	if err != nil {
		log.Fatalln(err)
	}
	data, _ = json.Marshal(receipt)
	log.Println(string(data))
}

func getState(lc *lightclient.LightClient, n uint64) (*ethpb2.BeaconStateBellatrix, *crypto.MerkleTree) {
	state, err := lc.Client.GetState(n)
	if err != nil {
		log.Fatalln(err)
	}
	stateTree := crypto.NewVectorMerkleTree(
		crypto.UintToHash(state.GenesisTime),
		common.BytesToHash(state.GenesisValidatorsRoot),
		crypto.UintToHash(uint64(state.Slot)),
		lightclient.MustHashTreeRoot(state.Fork),
		lightclient.MustHashTreeRoot(state.LatestBlockHeader),
		hashRootsVector(state.BlockRoots),
		hashRootsVector(state.StateRoots),
		hashRootsList(state.HistoricalRoots, lc.Spec.HistoricalRootsLimit),
		lightclient.MustHashTreeRoot(state.Eth1Data),
		hashEth1Datas(state.Eth1DataVotes, int(lc.Spec.SlotsPerEpoch*lc.Spec.EpochsPerEth1VotingPeriod)),
		crypto.UintToHash(state.Eth1DepositIndex),
		hashValidators(state.Validators, lc.Spec.ValidatorRegistryLimit),
		hashUint64List(state.Balances, lc.Spec.ValidatorRegistryLimit),
		hashRootsVector(state.RandaoMixes),
		hashUint64Vector(state.Slashings),
		hashUint8List(state.PreviousEpochParticipation, lc.Spec.ValidatorRegistryLimit),
		hashUint8List(state.CurrentEpochParticipation, lc.Spec.ValidatorRegistryLimit),
		crypto.BytesToMerkleHash(state.JustificationBits.Bytes()),
		lightclient.MustHashTreeRoot(state.PreviousJustifiedCheckpoint),
		lightclient.MustHashTreeRoot(state.CurrentJustifiedCheckpoint),
		lightclient.MustHashTreeRoot(state.FinalizedCheckpoint),
		hashUint64List(state.InactivityScores, lc.Spec.ValidatorRegistryLimit),
		lightclient.MustHashTreeRoot(state.CurrentSyncCommittee),
		lightclient.MustHashTreeRoot(state.NextSyncCommittee),
		lightclient.MustHashTreeRoot(state.LatestExecutionPayloadHeader),
	)
	return state, stateTree
}

func NewExecutionPayload(header *ethpb2.ExecutionPayloadHeader) ExecutionPayloadHeader {
	return ExecutionPayloadHeader{
		ParentHash:       common.BytesToHash(header.ParentHash),
		FeeRecipient:     common.BytesToAddress(header.FeeRecipient),
		StateRoot:        common.BytesToHash(header.StateRoot),
		ReceiptsRoot:     common.BytesToHash(header.ReceiptsRoot),
		LogsBloomRoot:    crypto.BytesToMerkleHash(header.LogsBloom),
		PrevRandao:       common.BytesToHash(header.PrevRandao),
		BlockNumber:      header.BlockNumber,
		GasLimit:         header.GasLimit,
		GasUsed:          header.GasUsed,
		Timestamp:        header.Timestamp,
		ExtraDataRoot:    crypto.NewPackedListMerkleTree(header.ExtraData, len(header.ExtraData), 1).Hash(),
		BaseFeePerGas:    new(big.Int).SetBytes(bytesutil.ReverseByteOrder(header.BaseFeePerGas)),
		BlockHash:        common.BytesToHash(header.BlockHash),
		TransactionsRoot: common.BytesToHash(header.TransactionsRoot),
	}
}

func hashRootsVector(rs [][]byte) common.Hash {
	chunks := make([]common.Hash, len(rs))
	for i, r := range rs {
		chunks[i] = common.BytesToHash(r)
	}
	return crypto.NewVectorMerkleTree(chunks...).Hash()
}

func hashRootsList(rs [][]byte, limit int) common.Hash {
	chunks := make([]common.Hash, len(rs))
	for i, r := range rs {
		chunks[i] = common.BytesToHash(r)
	}
	return crypto.NewListMerkleTree(chunks, limit).Hash()
}

func hashEth1Datas(ds []*ethpb2.Eth1Data, limit int) common.Hash {
	chunks := make([]common.Hash, len(ds))
	for i, d := range ds {
		chunks[i] = lightclient.MustHashTreeRoot(d)
	}
	return crypto.NewListMerkleTree(chunks, limit).Hash()
}

func hashValidators(vs []*ethpb2.Validator, limit int) common.Hash {
	chunks := make([]common.Hash, len(vs))
	for i, v := range vs {
		chunks[i] = lightclient.MustHashTreeRoot(v)
	}
	return crypto.NewListMerkleTree(chunks, limit).Hash()
}

func hashUint64List(vs []uint64, limit int) common.Hash {
	data := make([]byte, 8*len(vs))
	for i, x := range vs {
		binary.LittleEndian.PutUint64(data[i*8:], x)
	}
	return crypto.NewPackedListMerkleTree(data, len(vs), limit/4).Hash()
}

func hashUint64Vector(vs []uint64) common.Hash {
	data := make([]byte, 8*len(vs))
	for i, x := range vs {
		binary.LittleEndian.PutUint64(data[i*8:], x)
	}
	return crypto.NewPackedVectorMerkleTree(data).Hash()
}

func hashUint8List(vs []byte, limit int) common.Hash {
	return crypto.NewPackedListMerkleTree(vs, len(vs), limit/32).Hash()
}
