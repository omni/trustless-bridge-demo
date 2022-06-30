package main

import (
	"math/big"

	"github.com/ethereum/go-ethereum/common"
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
