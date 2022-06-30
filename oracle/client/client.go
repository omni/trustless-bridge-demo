package client

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/ethereum/go-ethereum/common"
	ethpb2 "github.com/prysmaticlabs/prysm/proto/prysm/v1alpha1"
)

type Eth2Client interface {
	GetSpec() (*ModelSpecData, error)
	GetGenesis() (*ModelGenesisData, error)
	GetBlock(slot uint64) (*ethpb2.BeaconBlockBellatrix, error)
	GetBlockByHash(hash common.Hash) (*ethpb2.BeaconBlockBellatrix, error)
	GetState(slot uint64) (*ethpb2.BeaconStateBellatrix, error)
}

var NotFoundError = errors.New("not found")

var _ Eth2Client = (*BeaconClient)(nil)

type BeaconClient struct {
	baseUrl string
	c       *http.Client
}

func NewClient(baseUrl string) Eth2Client {
	return &BeaconClient{
		baseUrl: baseUrl,
		c: &http.Client{
			Transport: http.DefaultTransport,
			Timeout:   10 * time.Minute,
		},
	}
}

func (b *BeaconClient) get(url string, out interface{}, ssz bool) error {
	fullUrl := b.baseUrl + url
	req, err := http.NewRequest("GET", fullUrl, nil)
	if err != nil {
		return fmt.Errorf("can't make request from url: %w", err)
	}
	if ssz {
		req.Header.Set("Accept", "application/octet-stream")
	}
	res, err := b.c.Do(req)
	if err != nil {
		return fmt.Errorf("can't fetch from url: %w", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		if res.StatusCode == http.StatusNotFound || res.StatusCode == http.StatusBadRequest {
			return NotFoundError
		}
		return fmt.Errorf("got error status code: %d", res.StatusCode)
	}

	if ssz {
		data, err := io.ReadAll(res.Body)
		if err != nil {
			return fmt.Errorf("can't read ssz: %w", err)
		}
		outSSZ := out.(interface{ UnmarshalSSZ(buf []byte) error })
		err = outSSZ.UnmarshalSSZ(data)
		if err != nil {
			return fmt.Errorf("can't unmarshal ssz: %w", err)
		}
		return nil
	}
	err = json.NewDecoder(res.Body).Decode(out)
	if err != nil {
		return fmt.Errorf("can't parse json into %T: %w", out, err)
	}
	return nil
}

func (b *BeaconClient) GetSpec() (*ModelSpecData, error) {
	data := new(ModelSpec)
	err := b.get("/eth/v1/config/spec", data, false)
	if err != nil {
		return nil, fmt.Errorf("can't fetch spec: %w", err)
	}
	return &data.Data, err
}

func (b *BeaconClient) GetGenesis() (*ModelGenesisData, error) {
	data := new(ModelGenesis)
	err := b.get("/eth/v1/beacon/genesis", data, false)
	if err != nil {
		return nil, fmt.Errorf("can't fetch genesis: %w", err)
	}
	return &data.Data, err
}

func (b *BeaconClient) GetBlock(slot uint64) (*ethpb2.BeaconBlockBellatrix, error) {
	url := fmt.Sprintf("/eth/v2/beacon/blocks/%d", slot)
	data := new(ethpb2.SignedBeaconBlockBellatrix)
	err := b.get(url, data, true)
	if err != nil {
		return nil, fmt.Errorf("can't fetch block: %w", err)
	}
	return data.Block, nil
}

func (b *BeaconClient) GetBlockByHash(hash common.Hash) (*ethpb2.BeaconBlockBellatrix, error) {
	url := fmt.Sprintf("/eth/v2/beacon/blocks/%s", hash)
	data := new(ethpb2.SignedBeaconBlockBellatrix)
	err := b.get(url, data, true)
	if err != nil {
		return nil, fmt.Errorf("can't fetch block: %w", err)
	}
	return data.Block, nil
}

func (b *BeaconClient) GetState(slot uint64) (*ethpb2.BeaconStateBellatrix, error) {
	url := fmt.Sprintf("/eth/v2/debug/beacon/states/%d", slot)
	data := new(ethpb2.BeaconStateBellatrix)
	err := b.get(url, data, true)
	if err != nil {
		return nil, fmt.Errorf("can't fetch block state: %w", err)
	}
	return data, nil
}
