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
	gethcrypto "github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/ethclient/gethclient"
	"github.com/ethereum/go-ethereum/rpc"

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

	key := gethcrypto.Keccak256Hash(common.BigToHash(big.NewInt(*msgNonce)).Bytes(), common.BigToHash(big.NewInt(0)).Bytes()).String()
	proof, err := sourceGethClient.GetProof(ctx, common.HexToAddress(*sourceAMB), []string{key}, big.NewInt(int64(syncedBlockNumber)))
	if err != nil {
		log.Fatalln(err)
	}

	accountProof := transformProof(proof.AccountProof)
	storageProof := transformProof(proof.StorageProof[0].Proof)
	data, err = contract.AMBABI.Pack("executeMessage", big.NewInt(int64(syncedBlockNumber)), msg, accountProof, storageProof)
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

func transformProof(proof []string) [][]byte {
	res := make([][]byte, len(proof))
	for i := range proof {
		res[i] = common.FromHex(proof[i])
	}
	return res
}
