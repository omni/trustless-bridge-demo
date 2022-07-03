package main

import (
	"context"
	"encoding/binary"
	"flag"
	"log"
	"strconv"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"

	"oracle/config"
	"oracle/contract"
	"oracle/lightclient"
)

var (
	sourceBeaconRPC     = flag.String("sourceBeaconRPC", "", "")
	targetRPC           = flag.String("targetRPC", "", "")
	lightClientContract = flag.String("lightClientContract", "", "")
	chainContract       = flag.String("chainContract", "", "")
	blockNumber         = flag.Uint64("blockNumber", 0, "")
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

	block, err := lc.Client.GetBlock("head")
	if err != nil {
		log.Fatalln(err)
	}

	latestSlot := uint64(block.Slot)
	if block.Body.ExecutionPayload == nil {
		log.Fatalln("latest beacon block has empty execution payload")
	}
	latestExecutionBlock := block.Body.ExecutionPayload.BlockNumber
	if latestExecutionBlock < *blockNumber {
		log.Fatalln("latest beacon block -> execution payload block number is less than requested block number")
	}
	l, r := lc.Spec.BellatrixForkEpoch*lc.Spec.SlotsPerEpoch, latestSlot
	for l < r {
		m := (l + r) / 2
		block, err = lc.Client.GetBlock(strconv.FormatUint(m, 10))
		if err != nil {
			log.Fatalln(err)
		}
		if block.Body.ExecutionPayload == nil || block.Body.ExecutionPayload.BlockNumber < *blockNumber {
			l = m + 1
		} else {
			r = m
		}
	}
	requiredBeaconBlock := l

	requiredBeaconBlockForFinalization := uint64(0)
	state, err := lc.Client.GetState(latestSlot)
	if err != nil {
		log.Fatalln(err)
	}
	if uint64(state.FinalizedCheckpoint.Epoch)*lc.Spec.SlotsPerEpoch >= requiredBeaconBlock {
		l, r = requiredBeaconBlock, latestSlot
		for l < r {
			m := (l + r) / 2
			state, err = lc.Client.GetState(m)
			if err != nil {
				log.Fatalln(err)
			}
			if uint64(state.FinalizedCheckpoint.Epoch)*lc.Spec.SlotsPerEpoch < requiredBeaconBlock {
				l = m + 1
			} else {
				r = m
			}
		}
		requiredBeaconBlockForFinalization = l
	}

	calldata, err2 := contract.BeaconLightClientABI.Pack("head")
	if err2 != nil {
		log.Fatalln(err2)
	}
	lcAddr := common.HexToAddress(*lightClientContract)
	chainAddr := common.HexToAddress(*chainContract)
	data, err := targetClient.CallContract(ctx, ethereum.CallMsg{
		To:   &lcAddr,
		Data: calldata,
	}, nil)
	if err != nil {
		log.Fatalln(err)
	}
	if len(data) != 32 {
		log.Fatalln("head() should return 32 bytes")
	}
	syncedBeaconSlot := binary.BigEndian.Uint64(data[24:32])
	data, err = targetClient.CallContract(ctx, ethereum.CallMsg{
		To:   &chainAddr,
		Data: calldata,
	}, nil)
	if err != nil {
		log.Fatalln(err)
	}
	if len(data) != 32 {
		log.Fatalln("head() should return 32 bytes")
	}
	syncedExecutionBlock := binary.BigEndian.Uint64(data[24:32])

	log.Printf("Requested execution block: %d\n", *blockNumber)
	log.Printf("Associated beacon block slot: %d\n", requiredBeaconBlock)
	if requiredBeaconBlockForFinalization == 0 {
		log.Printf("Beacon block %d is not yet finalized, latest finalized slot: %d\n", requiredBeaconBlock, uint64(state.FinalizedCheckpoint.Epoch)*lc.Spec.SlotsPerEpoch)
	} else {
		log.Printf("Beacon block with slot %d finalized: %d\n", requiredBeaconBlock, requiredBeaconBlockForFinalization)
	}
	log.Printf("Latest synced beacon slot on the other side: %d\n", syncedBeaconSlot)
	log.Printf("Latest synced execution block on the other side: %d\n", syncedExecutionBlock)
}
