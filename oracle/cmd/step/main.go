package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"bls-sandbox/config"
	"bls-sandbox/contract"
	"bls-sandbox/lightclient"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/ethclient"
)

func main() {
	configFile := flag.String("config", "./config.yml", "")
	currentSlot := flag.Uint64("currentSlot", 0, "")
	targetSlot := flag.Uint64("targetSlot", 0, "")
	outputFile := flag.String("output", "./proof_<from>_<to>.json", "")
	n := flag.Int("n", 1, "")
	finality := flag.Bool("finality", true, "")
	flag.Parse()

	ctx := context.Background()

	cfg, err := config.ReadFromFile(*configFile)
	if err != nil {
		log.Fatalln(err)
	}

	lightClient, err := lightclient.NewLightClient(cfg.Eth2, *finality)
	if err != nil {
		log.Fatalln(err)
	}

	slot := *currentSlot
	if slot == 0 {
		if cfg.Eth1 == nil {
			log.Fatalln("missing eth1 client config")
		}

		eth1Client, err := ethclient.Dial(cfg.Eth1.Client.URL)
		if err != nil {
			log.Fatalln(err)
		}

		contractABI, err := contract.LightClientABI()
		if err != nil {
			log.Fatalln(err)
		}
		data, err := contractABI.Pack("head")
		if err != nil {
			log.Fatalln(err)
		}

		res, err := eth1Client.CallContract(ctx, ethereum.CallMsg{
			To:   &cfg.Eth1.Contract,
			Gas:  100000,
			Data: data,
		}, nil)
		if err != nil {
			log.Fatalln(err)
		}
		slot = binary.BigEndian.Uint64(res[24:32])
	}

	target := *targetSlot
	for i := 0; i < *n; i++ {
		log.Printf("Searching for update from slot %d\n", slot)
		update, err := lightClient.MakeUpdate(slot, target)
		target = 0
		if err != nil {
			log.Fatalln(err)
		}

		outputFilePath := *outputFile
		outputFilePath = strings.ReplaceAll(outputFilePath, "<from>", fmt.Sprint(slot))
		updateTargerSlot := update.AttestedHeader.Slot
		if update.FinalizedHeader.Slot > 0 {
			updateTargerSlot = update.FinalizedHeader.Slot
		}
		outputFilePath = strings.ReplaceAll(outputFilePath, "<to>", fmt.Sprint(updateTargerSlot))
		output, err := os.OpenFile(outputFilePath, os.O_CREATE|os.O_RDWR, os.ModePerm)
		if err != nil {
			log.Fatalln(fmt.Errorf("can't open file: %w", err))
		}
		err = json.NewEncoder(output).Encode(update)
		if err != nil {
			log.Fatalln(fmt.Errorf("can't marshal update struct: %w", err))
		}
		err = output.Close()
		if err != nil {
			log.Fatalln(fmt.Errorf("can't close file: %w", err))
		}

		slot = updateTargerSlot
	}
}
