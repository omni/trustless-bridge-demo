package main

import (
	"context"
	"encoding/json"
	"flag"
	"log"
	"os"

	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"

	"oracle/config"
	"oracle/contract"
	"oracle/lightclient"
	"oracle/sender"
)

var (
	configFile     = flag.String("config", "./config.yml", "")
	proofFilePath  = flag.String("proof", "", "")
	applyCandidate = flag.Bool("apply", false, "")
)

func main() {
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
}
