package main

import (
	"bls-sandbox/config"
	"bls-sandbox/contract"
	"bls-sandbox/lightclient"
	"bls-sandbox/sender"

	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/big"
	"os"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/prysmaticlabs/go-bitfield"
)

func main() {
	configFile := flag.String("config", "./config.yml", "")
	proofFilePath := flag.String("proof", "", "")
	applyCandidate := flag.Bool("apply", false, "")
	flag.Parse()

	ctx := context.Background()

	cfg, err := config.ReadFromFile(*configFile)
	if err != nil {
		log.Fatalln(err)
	}

	eth1Client, err := ethclient.Dial(cfg.Eth1.Client.URL)
	if err != nil {
		log.Fatalln(err)
	}

	s, err := sender.NewTxSender(ctx, eth1Client, cfg.Eth1.Keystore, cfg.Eth1.KeystorePassword)
	if err != nil {
		log.Fatalln(err)
	}

	var data []byte
	var proof lightclient.Update
	if *applyCandidate {
		data, err = contract.BeaconLightClientABI.Pack("applyCandidate")
		if err != nil {
			log.Fatalln(err)
		}
	} else {
		var f *os.File
		f, err = os.OpenFile(*proofFilePath, os.O_RDONLY, os.ModePerm)
		if err != nil {
			log.Fatalln(err)
		}
		err = json.NewDecoder(f).Decode(&proof)
		if err != nil {
			log.Fatalln(err)
		}
		data, err = contract.BeaconLightClientABI.Pack("step", &proof)
		if err != nil {
			log.Fatalln(err)
		}
	}

	gas, err := eth1Client.EstimateGas(ctx, ethereum.CallMsg{
		To:   &cfg.Eth1.Contract,
		Data: data,
	})
	if err != nil {
		log.Fatalln("estimate gas failed:", err)
	}
	log.Printf("Estimated gas: %d", gas)
	signedTx, err := s.SendTx(ctx, &types.DynamicFeeTx{
		GasTipCap: big.NewInt(1e9),
		GasFeeCap: big.NewInt(1e9),
		Gas:       gas + gas/2,
		To:        &cfg.Eth1.Contract,
		Data:      data,
	})
	if err != nil {
		log.Fatalln(err)
	}
	log.Printf("Sent tx: %s\n", signedTx.Hash())
	receipt, err := s.WaitReceipt(ctx, signedTx)
	if err != nil {
		log.Fatalln(err)
	}
	for _, e := range receipt.Logs {
		if len(e.Topics) > 0 {
			if event, err2 := contract.BeaconLightClientABI.EventByID(e.Topics[0]); err2 == nil {
				m := make(map[string]interface{})
				if len(e.Data) > 0 {
					if err3 := event.Inputs.UnpackIntoMap(m, e.Data); err3 != nil {
						log.Printf("can't unpack data for event %s, %x: %w", event.Name, e.Data, err3)
						continue
					}
				}
				if len(e.Topics) > 1 {
					indexed := Indexed(event.Inputs)
					if err3 := abi.ParseTopicsIntoMap(m, indexed, e.Topics[1:]); err3 != nil {
						log.Printf("can't unpack topics for event %s: %w", event.Name, err3)
						continue
					}
				}
				s := fmt.Sprintf("\t%s(", event.Name)
				for i, arg := range event.Inputs {
					if i > 0 {
						s += ", "
					}
					v := m[arg.Name]
					if vb, ok := v.([32]uint8); ok {
						s += common.BytesToHash(vb[:]).String()
					} else {
						s += fmt.Sprint(v)
					}
				}
				log.Println(s + ")")
			}
		}
	}
	if *applyCandidate {
		log.Printf("Used gas: %d\n", receipt.GasUsed)
	} else {
		bitList := bitfield.Bitvector512(append(proof.SyncAggregateBitList[0].Bytes(), proof.SyncAggregateBitList[1].Bytes()...))
		log.Printf("Used gas (%d/%d): %d\n", bitList.Count(), 512, receipt.GasUsed)
	}
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
