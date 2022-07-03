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
	"github.com/ethereum/go-ethereum/ethdb/memorydb"
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/ethereum/go-ethereum/trie"

	"oracle/contract"
	"oracle/sender"
)

var (
	sourceRPC     = flag.String("sourceRPC", "", "")
	targetRPC     = flag.String("targetRPC", "", "")
	sourceAMB     = flag.String("sourceAMB", "", "")
	targetAMB     = flag.String("targetAMB", "", "")
	targetLCChain = flag.String("targetLCChain", "", "")
	msgNonce      = flag.Int64("msgNonce", 0, "")
	keystore      = flag.String("keystore", "", "")
	keystorePass  = flag.String("keystorePass", "", "")
)

func main() {
	flag.Parse()

	ctx := context.Background()

	sourceClient, err := ethclient.Dial(*sourceRPC)
	if err != nil {
		log.Fatalln(err)
	}
	targetClient, err := ethclient.Dial(*targetRPC)
	if err != nil {
		log.Fatalln(err)
	}

	topics := [][]common.Hash{
		{contract.AMBABI.Events["SentMessage"].ID},
		nil,
		{common.BigToHash(big.NewInt(*msgNonce))},
	}
	logs, err := sourceClient.FilterLogs(ctx, ethereum.FilterQuery{
		Addresses: []common.Address{common.HexToAddress(*sourceAMB)},
		Topics:    topics,
	})
	if err != nil {
		log.Fatalln(err)
	}
	if len(logs) == 0 {
		log.Fatalln("SentMessage log not found in the source network")
	}
	if len(logs) > 1 {
		log.Fatalln("should be exactly one SentMessage log")
	}
	data := logs[0].Data
	length := binary.BigEndian.Uint64(data[56:64])

	msg := data[64 : 64+length]
	blockNumber := logs[0].BlockNumber

	to := common.HexToAddress(*targetLCChain)
	cd, err := contract.LightClientChainABI.Pack("head")
	if err != nil {
		log.Fatalln(err)
	}
	data, err = targetClient.CallContract(ctx, ethereum.CallMsg{
		To:   &to,
		Data: cd,
	}, nil)
	if err != nil {
		log.Fatalln(err)
	}
	if len(data) != 32 {
		log.Fatalln("head() should return 32 bytes")
	}
	syncedBlockNumber := binary.BigEndian.Uint64(data[24:32])
	if syncedBlockNumber < blockNumber {
		log.Fatalf("not yet synced to the desired block number, %d < %d \n", syncedBlockNumber, blockNumber)
	}

	cd, err = contract.LightClientChainABI.Pack("stateRoot", big.NewInt(int64(blockNumber)))
	if err != nil {
		log.Fatalln(err)
	}
	data, err = targetClient.CallContract(ctx, ethereum.CallMsg{
		To:   &to,
		Data: cd,
	}, nil)
	if err != nil {
		log.Fatalln(err)
	}
	if len(data) != 32 {
		log.Fatalln("stateRoot(uint256) should return 32 bytes")
	}
	if common.BytesToHash(data) == (common.Hash{}) {
		log.Fatalf("state root for execution block %d is missing\n", blockNumber)
	}

	block, err := sourceClient.BlockByHash(ctx, logs[0].BlockHash)
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
		if i == int(logs[0].TxIndex) {
			logIndex = int(logs[0].Index - receipt.Logs[0].Index)
		}
		key := rlp.AppendUint64(nil, uint64(i))
		value, err2 := receipt.MarshalBinary()
		if err2 != nil {
			log.Fatalln(err2)
		}
		receiptTrie.Update(key, value)
	}
	proof := &OrderedDB{}
	err = receiptTrie.Prove(rlp.AppendUint64(nil, uint64(logs[0].TxIndex)), 0, proof)
	if err != nil {
		log.Fatalln(err)
	}

	data, err = contract.AMBABI.Pack(
		"executeMessageFromLog",
		big.NewInt(int64(blockNumber)),
		big.NewInt(int64(logs[0].TxIndex)),
		big.NewInt(int64(logIndex)),
		msg,
		proof.Proof,
	)
	if err != nil {
		log.Fatalln(err)
	}

	s, err := sender.NewTxSender(ctx, targetClient, *keystore, *keystorePass)
	if err != nil {
		log.Fatalln(err)
	}

	to = common.HexToAddress(*targetAMB)
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
