package abi

import (
	"bytes"
	_ "embed"

	"github.com/ethereum/go-ethereum/accounts/abi"
)

//go:embed abi.json
var rawABI []byte

func MustParseABI(raw []byte) abi.ABI {
	res, err := abi.JSON(bytes.NewReader(raw))
	if err != nil {
		panic(err)
	}
	return res
}

var ABI = MustParseABI(rawABI)
