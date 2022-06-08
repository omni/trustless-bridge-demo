package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"

	"bls-sandbox/config"
	"bls-sandbox/contract"
	"bls-sandbox/lightclient"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/ethclient"
)

func main() {
	configFile := flag.String("config", "./config.yml", "")
	interval := flag.Duration("interval", time.Minute, "")
	flag.Parse()

	ctx := context.Background()

	cfg, err := config.ReadFromFile(*configFile)
	if err != nil {
		log.Fatalln(err)
	}

	lightClient, err := lightclient.NewLightClient(cfg.Eth2, true)
	if err != nil {
		log.Fatalln(err)
	}

	eth1Client, err := ethclient.Dial(cfg.Eth1.Client.URL)
	if err != nil {
		log.Fatalln(err)
	}

	contractABI, err := contract.LightClientABI()
	if err != nil {
		log.Fatalln(err)
	}
	data, err := contractABI.Pack("headSlot")
	if err != nil {
		log.Fatalln(err)
	}

	res, err := eth1Client.CallContract(ctx, ethereum.CallMsg{
		To:   &cfg.Eth1.Contract,
		Gas:  100000,
		Data: data,
	}, nil)
	slotBN, err := contractABI.Unpack("headSlot", res)
	if err != nil {
		log.Fatalln(err)
	}
	slot := slotBN[0].(*big.Int).Uint64()

	ticker := time.NewTicker(*interval)
	sender, err := NewTxSender(ctx, eth1Client, cfg.Eth1.Keystore, cfg.Eth1.KeystorePassword)
	if err != nil {
		log.Fatalln(err)
	}
	for {
		log.Printf("Searching for update from slot %d\n", slot)
		update, err := lightClient.MakeUpdate(slot, 0)
		if err != nil {
			log.Fatalln(err)
		}
		if update != nil {
			updateTargerSlot := update.AttestedHeader.Slot
			if update.FinalizedHeader.Slot > 0 {
				updateTargerSlot = update.FinalizedHeader.Slot
			}

			data, err = contractABI.Pack("step", &update)
			if err != nil {
				log.Fatalln(err)
			}

			gas, err := eth1Client.EstimateGas(ctx, ethereum.CallMsg{
				To:   &cfg.Eth1.Contract,
				Data: data,
			})
			if err != nil {
				log.Fatalln("estimate gas failed:", err)
			}
			log.Printf("Estimated gas: %d", gas)
			signedTx, err := sender.SendTx(ctx, &types.DynamicFeeTx{
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
			receipt, err := sender.WaitReceipt(ctx, signedTx)
			if err != nil {
				log.Fatalln(err)
			}
			PrintReceipt(contractABI, receipt)

			slot = updateTargerSlot
		} else {
			log.Printf("current slot %d, nothing to update...\n", slot)
		}

		select {
		case <-ticker.C:
		}
	}
}

func PrintReceipt(contractABI abi.ABI, receipt *types.Receipt) {
	for _, e := range receipt.Logs {
		if len(e.Topics) > 0 {
			if event, err2 := contractABI.EventByID(e.Topics[0]); err2 == nil {
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
	log.Printf("Used gas: %d\n", receipt.GasUsed)
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
