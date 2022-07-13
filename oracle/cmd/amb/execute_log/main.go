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
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/ethdb/memorydb"
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/ethereum/go-ethereum/trie"

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

	sourceClient, err := ethclient.Dial(*sourceRPC)
	if err != nil {
		log.Fatalln(err)
	}
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

	block, err := sourceClient.BlockByHash(ctx, sentLog.BlockHash)
	if err != nil {
		log.Fatalln(err)
	}
	receiptTrie, _ := trie.New(common.Hash{}, trie.NewDatabase(memorydb.New()))
	logIndex := 0
	for i, tx := range block.Transactions() {
		receipt, err2 := sourceClient.TransactionReceipt(ctx, tx.Hash())
		if err2 != nil {
			log.Fatalln(err2)
		}
		if i == int(sentLog.TxIndex) {
			logIndex = int(sentLog.Index - receipt.Logs[0].Index)
		}
		key := rlp.AppendUint64(nil, uint64(i))
		value, err2 := receipt.MarshalBinary()
		if err2 != nil {
			log.Fatalln(err2)
		}
		receiptTrie.Update(key, value)
	}
	proof := &OrderedDB{}
	err = receiptTrie.Prove(rlp.AppendUint64(nil, uint64(sentLog.TxIndex)), 0, proof)
	if err != nil {
		log.Fatalln(err)
	}

	receiptsRootProof, err := lc.MakeExecutionPayloadReceiptsRootProof(syncedSlot, sourceSlot)
	if err != nil {
		log.Fatalln(err)
	}

	data, err := contract.AMBABI.Pack(
		"executeMessageFromLog",
		big.NewInt(int64(syncedSlot)),
		big.NewInt(int64(sourceSlot)),
		big.NewInt(int64(sentLog.TxIndex)),
		big.NewInt(int64(logIndex)),
		msg,
		receiptsRootProof,
		proof.Proof,
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

type OrderedDB struct {
	Proof [][]byte
}

func (db *OrderedDB) Put(_ []byte, value []byte) error {
	db.Proof = append(db.Proof, value)
	return nil
}

// Delete removes the key from the key-value data store.
func (db *OrderedDB) Delete(key []byte) error {
	return nil
}
