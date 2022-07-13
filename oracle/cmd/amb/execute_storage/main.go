package main

import (
	"context"
	"encoding/binary"
	"flag"
	"fmt"
	"log"
	"math/big"
	"strconv"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	gethcrypto "github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/ethclient/gethclient"
	"github.com/ethereum/go-ethereum/rpc"

	"oracle/config"
	"oracle/contract"
	"oracle/lightclient"
	"oracle/sender"
)

var (
	sourceBeaconRPC = flag.String("sourceBeaconRPC", "", "")
	sourceRPC       = flag.String("sourceRPC", "", "")
	targetRPC       = flag.String("targetRPC", "", "")
	sourceAMB       = flag.String("sourceAMB", "", "")
	targetAMB       = flag.String("targetAMB", "", "")
	targetLC        = flag.String("targetLC", "", "")
	msgNonce        = flag.Int64("msgNonce", 0, "")
	keystore        = flag.String("keystore", "", "")
	keystorePass    = flag.String("keystorePass", "", "")
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

	sourceRawClient, err := rpc.Dial(*sourceRPC)
	if err != nil {
		log.Fatalln(err)
	}
	sourceClient := ethclient.NewClient(sourceRawClient)
	sourceGethClient := gethclient.New(sourceRawClient)
	targetClient, err := ethclient.Dial(*targetRPC)
	if err != nil {
		log.Fatalln(err)
	}

	sentLog, err := FindSentMessageLog(ctx, sourceClient, common.HexToAddress(*sourceAMB), *msgNonce)
	if err != nil {
		log.Fatalln(err)
	}

	length := binary.BigEndian.Uint64(sentLog.Data[56:64])
	msg := sentLog.Data[64 : 64+length]

	syncedSlot, err := GetSyncedSlot(ctx, targetClient, common.HexToAddress(*targetLC))
	if err != nil {
		log.Fatalln(err)
	}

	syncedBlock, err := lc.Client.GetBlock(strconv.FormatUint(syncedSlot, 10))
	if err != nil {
		log.Fatalln(err)
	}
	syncedBlockNumber := syncedBlock.Body.ExecutionPayload.BlockNumber
	if syncedBlockNumber < sentLog.BlockNumber {
		log.Fatalf("not yet synced to the desired block number, %d < %d \n", syncedBlockNumber, sentLog.BlockNumber)
	}

	sourceSlot, err := lc.FindBeaconBlockByExecutionBlockNumber(sentLog.BlockNumber)
	if err != nil {
		log.Fatalln(err)
	}

	key := gethcrypto.Keccak256Hash(common.BigToHash(big.NewInt(*msgNonce)).Bytes(), common.BigToHash(big.NewInt(0)).Bytes()).String()

	sourceProofSlot := int64(syncedSlot)
	var stateRootProof []common.Hash
	var accountProof, storageProof [][]byte

	foundVerifiedStorageRoot, verifiedSlot, err := FindVerifiedStorageRootLog(ctx, targetClient, common.HexToAddress(*targetAMB), int64(sourceSlot))
	if err != nil {
		log.Fatalln(err)
	}

	if foundVerifiedStorageRoot {
		log.Printf("found already verified storage root log at slot %d\n", verifiedSlot)
		sourceProofSlot = verifiedSlot

		syncedBlock, err = lc.Client.GetBlock(strconv.FormatUint(uint64(verifiedSlot), 10))
		if err != nil {
			log.Fatalln(err)
		}
		proof, err := sourceGethClient.GetProof(ctx, common.HexToAddress(*sourceAMB), []string{key}, big.NewInt(int64(syncedBlock.Body.ExecutionPayload.BlockNumber)))
		if err != nil {
			log.Fatalln(err)
		}
		storageProof = transformProof(proof.StorageProof[0].Proof)
	} else {
		proof, err := sourceGethClient.GetProof(ctx, common.HexToAddress(*sourceAMB), []string{key}, big.NewInt(int64(syncedBlockNumber)))
		if err != nil {
			log.Fatalln(err)
		}
		accountProof = transformProof(proof.AccountProof)
		storageProof = transformProof(proof.StorageProof[0].Proof)

		stateRootProof, err = lc.MakeExecutionPayloadStateRootProof(syncedSlot)
		if err != nil {
			log.Fatalln(err)
		}
	}

	data, err := contract.AMBABI.Pack(
		"executeMessage",
		big.NewInt(sourceProofSlot),
		msg,
		stateRootProof,
		accountProof,
		storageProof,
	)
	if err != nil {
		log.Fatalln(err)
	}

	s, err := sender.NewTxSender(ctx, targetClient, *keystore, *keystorePass)
	if err != nil {
		log.Fatalln(err)
	}

	to := common.HexToAddress(*targetAMB)
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
	log.Println(contract.FormatReceipt(contract.AMBABI, receipt))
}

func GetSyncedSlot(ctx context.Context, client *ethclient.Client, addr common.Address) (uint64, error) {
	cd, err := contract.BeaconLightClientABI.Pack("head")
	if err != nil {
		return 0, fmt.Errorf("can't pack head() call")
	}
	data, err := client.CallContract(ctx, ethereum.CallMsg{
		To:   &addr,
		Data: cd,
	}, nil)
	if err != nil {
		return 0, fmt.Errorf("can't make eth_call request: %w", err)
	}
	if len(data) != 32 {
		return 0, fmt.Errorf("call to head() should return 32 bytes, got %d instead", len(data))
	}
	return binary.BigEndian.Uint64(data[24:32]), nil
}

func FindSentMessageLog(ctx context.Context, client *ethclient.Client, addr common.Address, nonce int64) (*types.Log, error) {
	topics := [][]common.Hash{
		{contract.AMBABI.Events["SentMessage"].ID},
		nil,
		{common.BigToHash(big.NewInt(nonce))},
	}
	logs, err := client.FilterLogs(ctx, ethereum.FilterQuery{
		Addresses: []common.Address{addr},
		Topics:    topics,
	})
	if err != nil {
		return nil, fmt.Errorf("can't filter logs: %w", err)
	}
	if len(logs) == 0 {
		return nil, fmt.Errorf("can't find log with given nonce: %d", nonce)
	}
	if len(logs) > 1 {
		return nil, fmt.Errorf("found more than single SentMessage log: %d were found", len(logs))
	}
	return &logs[0], nil
}

func FindVerifiedStorageRootLog(ctx context.Context, client *ethclient.Client, addr common.Address, minSlot int64) (bool, int64, error) {
	topics := [][]common.Hash{
		{contract.AMBABI.Events["VerifiedStorageRoot"].ID},
	}
	logs, err := client.FilterLogs(ctx, ethereum.FilterQuery{
		Addresses: []common.Address{addr},
		Topics:    topics,
	})
	if err != nil {
		return false, 0, fmt.Errorf("can't filter logs: %w", err)
	}
	for _, l := range logs {
		slot := l.Topics[1].Big().Int64()
		if slot >= minSlot {
			return true, slot, nil
		}
	}
	return false, 0, nil
}

func transformProof(proof []string) [][]byte {
	res := make([][]byte, len(proof))
	for i := range proof {
		res[i] = common.FromHex(proof[i])
	}
	return res
}
