package contract

import (
	"bytes"
	_ "embed"

	"github.com/ethereum/go-ethereum/accounts/abi"
)

//go:embed abi.json
var ABI []byte

func LightClientABI() (abi.ABI, error) {
	return abi.JSON(bytes.NewReader(ABI))
}
