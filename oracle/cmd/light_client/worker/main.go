package main

import (
	"context"
	"encoding/binary"
	"flag"
	"log"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"

	"oracle/config"
	"oracle/contract"
	"oracle/lightclient"
	"oracle/sender"
)

var (
	configFile = flag.String("config", "./config.yml", "")
	interval   = flag.Duration("interval", time.Minute, "")
)

func main() {
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

	data, err := contract.BeaconLightClientABI.Pack("head")
	if err != nil {
		log.Fatalln(err)
	}

	res, err := eth1Client.CallContract(ctx, ethereum.CallMsg{
		To:   &cfg.Eth1.Contract,
		Data: data,
	}, nil)
	if err != nil {
		log.Fatalln(err)
	}
	slot := binary.BigEndian.Uint64(res[24:32])

	ticker := time.NewTicker(*interval)
	s, err := sender.NewTxSender(ctx, eth1Client, cfg.Eth1.Keystore, cfg.Eth1.KeystorePassword)
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

			data, err = contract.BeaconLightClientABI.Pack("step", &update)
			if err != nil {
				log.Fatalln(err)
			}

			signedTx, err := s.SendTx(ctx, &types.DynamicFeeTx{
				To:   &cfg.Eth1.Contract,
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
			log.Println(contract.FormatReceipt(contract.BeaconLightClientABI, receipt))

			slot = updateTargerSlot
		} else {
			log.Printf("current slot %d, nothing to update...\n", slot)
		}

		select {
		case <-ticker.C:
		case <-ctx.Done():
			break
		}
	}
}
