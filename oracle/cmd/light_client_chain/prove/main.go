package main

import (
	"context"
	"encoding/binary"
	"flag"
	"log"
	"math/big"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"

	"oracle/config"
	"oracle/contract"
	"oracle/crypto"
	"oracle/lightclient"
	"oracle/sender"
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

	ctx := context.Background()

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
		data, err2 := targetClient.CallContract(ctx, ethereum.CallMsg{
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
		state, stateTree, err2 := lc.GetBeaconState(*startSlot)
		if err2 != nil {
			log.Fatalln(err2)
		}
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
		state, stateTree, err2 := lc.GetBeaconState(*startSlot)
		if err2 != nil {
			log.Fatalln(err2)
		}
		state2, stateTree2, err2 := lc.GetBeaconState(*targetSlot)
		if err2 != nil {
			log.Fatalln(err2)
		}
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
		state, stateTree, err2 := lc.GetBeaconState(*startSlot)
		if err2 != nil {
			log.Fatalln(err2)
		}
		state2, _, err2 := lc.GetBeaconState(historicalBatchSlot)
		if err2 != nil {
			log.Fatalln(err2)
		}
		state3, stateTree3, err2 := lc.GetBeaconState(*targetSlot)
		if err2 != nil {
			log.Fatalln(err2)
		}

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

	s, err := sender.NewTxSender(ctx, targetClient, *keystore, *keystorePass)
	if err != nil {
		log.Fatalln(err)
	}

	to := common.HexToAddress(*chainContract)
	signedTx, err := s.SendTx(ctx, &types.DynamicFeeTx{
		To:   &to,
		Data: data,
	})
	if err != nil {
		log.Fatalln(err)
	}
	log.Printf("Sent tx: %s\n", signedTx.Hash())
	receipt, err := s.WaitReceipt(ctx, signedTx)
	if err != nil {
		log.Fatalln(err)
	}
	log.Println(contract.FormatReceipt(contract.LightClientChainABI, receipt))
}
