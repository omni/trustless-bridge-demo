package main

import (
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/prysmaticlabs/prysm/encoding/bytesutil"
	ethpb2 "github.com/prysmaticlabs/prysm/proto/prysm/v1alpha1"

	"oracle/crypto"
)

type ExecutionPayloadHeader struct {
	ParentHash       common.Hash    `json:"parentHash" abi:"parentHash"`
	FeeRecipient     common.Address `json:"feeRecipient" abi:"feeRecipient"`
	StateRoot        common.Hash    `json:"stateRoot" abi:"stateRoot"`
	ReceiptsRoot     common.Hash    `json:"receiptsRoot" abi:"receiptsRoot"`
	LogsBloomRoot    common.Hash    `json:"logsBloomRoot" abi:"logsBloomRoot"`
	PrevRandao       common.Hash    `json:"prevRandao" abi:"prevRandao"`
	BlockNumber      uint64         `json:"blockNumber" abi:"blockNumber"`
	GasLimit         uint64         `json:"gasLimit" abi:"gasLimit"`
	GasUsed          uint64         `json:"gasUsed" abi:"gasUsed"`
	Timestamp        uint64         `json:"timestamp" abi:"timestamp"`
	ExtraDataRoot    common.Hash    `json:"extraDataRoot" abi:"extraDataRoot"`
	BaseFeePerGas    *big.Int       `json:"baseFeePerGas" abi:"baseFeePerGas"`
	BlockHash        common.Hash    `json:"blockHash" abi:"blockHash"`
	TransactionsRoot common.Hash    `json:"transactionsRoot" abi:"transactionsRoot"`
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
