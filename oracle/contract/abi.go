package contract

import (
	"bytes"
	_ "embed"

	"github.com/ethereum/go-ethereum/accounts/abi"
)

//go:embed amb_abi.json
var ambABI []byte

//go:embed beacon_light_client_abi.json
var beaconLightClientABI []byte

//go:embed light_client_chain_abi.json
var lightClientChainABI []byte

func MustParseABI(raw []byte) abi.ABI {
	res, err := abi.JSON(bytes.NewReader(raw))
	if err != nil {
		panic(err)
	}
	return res
}

var AMBABI = MustParseABI(ambABI)
var BeaconLightClientABI = MustParseABI(beaconLightClientABI)
var LightClientChainABI = MustParseABI(lightClientChainABI)
