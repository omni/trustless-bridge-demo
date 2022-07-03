package contract

import (
	"fmt"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/core/types"
)

func FormatReceipt(contractABI abi.ABI, receipt *types.Receipt) string {
	res := strings.Repeat("#", 50)
	res += fmt.Sprintf("\nTx hash: %s\n", receipt.TxHash)
	res += fmt.Sprintf("Block number: %d\n", receipt.BlockNumber)
	res += fmt.Sprintf("Status: %d\n", receipt.Status)
	res += fmt.Sprintf("Gas used: %d\n", receipt.GasUsed)
	if len(receipt.Logs) > 0 {
		res += "Logs:\n"
	}
	for _, e := range receipt.Logs {
		if len(e.Topics) > 0 {
			if event, err2 := contractABI.EventByID(e.Topics[0]); err2 == nil {
				m := make(map[string]interface{})
				if len(e.Data) > 0 {
					if err3 := event.Inputs.UnpackIntoMap(m, e.Data); err3 != nil {
						res += fmt.Sprintf("\t%s(raw: %s)\n", event.Name, hexutil.Encode(e.Data))
						continue
					}
				}
				if len(e.Topics) > 1 {
					indexed := Indexed(event.Inputs)
					if err3 := abi.ParseTopicsIntoMap(m, indexed, e.Topics[1:]); err3 != nil {
						res += fmt.Sprintf("\t%s(raw: %s)\n", event.Name, hexutil.Encode(e.Data))
						continue
					}
				}
				res += fmt.Sprintf("\t%s(", event.Name)
				for i, arg := range event.Inputs {
					if i > 0 {
						res += ", "
					}
					res += arg.Name + ": "
					v := m[arg.Name]
					if vb, ok := v.([32]uint8); ok {
						res += hexutil.Encode(vb[:])
					} else if vb2, ok2 := v.([]uint8); ok2 {
						res += hexutil.Encode(vb2)
					} else {
						res += fmt.Sprint(v)
					}
				}
				res += ")\n"
			}
		}
	}
	res += strings.Repeat("#", 50)
	return res
}

func Indexed(args abi.Arguments) abi.Arguments {
	var indexed abi.Arguments
	for _, arg := range args {
		if arg.Indexed {
			indexed = append(indexed, arg)
		}
	}
	return indexed
}
