package sender

import (
	"context"
	"errors"
	"fmt"
	"math/big"
	"os"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/keystore"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
)

type TxSender struct {
	Client       *ethclient.Client
	ChainID      *big.Int
	MaxFeePerGas *big.Int
	MaxTipPerGas *big.Int
	Nonce        uint64
	acc          *keystore.Key
	signer       types.Signer
}

func NewTxSender(ctx context.Context, eth1Client *ethclient.Client, keystorePath string, keystorePassword string) (*TxSender, error) {
	file, err := os.ReadFile(keystorePath)
	if err != nil {
		return nil, fmt.Errorf("can't read keystore file: %w", err)
	}
	acc, err := keystore.DecryptKey(file, keystorePassword)
	if err != nil {
		return nil, fmt.Errorf("can't decrypt keystore file: %w", err)
	}

	chainID, err := eth1Client.ChainID(ctx)
	if err != nil {
		return nil, fmt.Errorf("can't get chain id: %w", err)
	}
	nonce, err := eth1Client.NonceAt(ctx, acc.Address, nil)
	if err != nil {
		return nil, fmt.Errorf("can't get account starting nonce: %w", err)
	}

	return &TxSender{
		Client:       eth1Client,
		ChainID:      chainID,
		MaxFeePerGas: big.NewInt(1e9),
		MaxTipPerGas: big.NewInt(1e9),
		Nonce:        nonce,
		acc:          acc,
		signer:       types.NewLondonSigner(chainID),
	}, nil
}

func (s *TxSender) SendTx(ctx context.Context, tx *types.DynamicFeeTx) (*types.Transaction, error) {
	tx.ChainID = s.ChainID
	if tx.GasFeeCap == nil {
		tx.GasFeeCap = s.MaxFeePerGas
	}
	if tx.GasTipCap == nil {
		tx.GasTipCap = s.MaxTipPerGas
	}
	tx.Nonce = s.Nonce
	if tx.Gas == 0 {
		gas, err := s.Client.EstimateGas(ctx, ethereum.CallMsg{
			From:       s.acc.Address,
			To:         tx.To,
			GasFeeCap:  tx.GasFeeCap,
			GasTipCap:  tx.GasTipCap,
			Value:      tx.Value,
			Data:       tx.Data,
			AccessList: tx.AccessList,
		})
		if err != nil {
			return nil, fmt.Errorf("gas estimation failed: %w", err)
		}
		tx.Gas = gas * 3 / 2
	}
	signedTx, err := types.SignNewTx(s.acc.PrivateKey, s.signer, tx)
	if err != nil {
		return nil, err
	}
	err = s.Client.SendTransaction(ctx, signedTx)
	if err != nil {
		return nil, err
	}
	s.Nonce += 1
	return signedTx, nil
}

func (s *TxSender) WaitReceipt(ctx context.Context, tx *types.Transaction) (*types.Receipt, error) {
	for {
		receipt, err := s.Client.TransactionReceipt(ctx, tx.Hash())
		if err != nil {
			if errors.Is(err, ethereum.NotFound) {
				t := time.NewTimer(time.Second * 5)
				select {
				case <-ctx.Done():
					return nil, ctx.Err()
				case <-t.C:
					continue
				}
			}
			return nil, err
		}
		return receipt, nil
	}
}
