package config

import (
	"fmt"
	"os"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"gopkg.in/yaml.v3"
)

type Config struct {
	Eth1 *Eth1Config `yaml:"eth1"`
	Eth2 Eth2Config  `yaml:"eth2"`
}

type Eth1Config struct {
	Client           HTTPClientConfig `yaml:"client"`
	Contract         common.Address   `yaml:"contract"`
	Keystore         string           `yaml:"keystore"`
	KeystorePassword string           `yaml:"keystore_password"`
}

type Eth2Config struct {
	Client  HTTPClientConfig `yaml:"client"`
	Genesis *GenesisConfig   `yaml:"genesis"`
	Spec    *SpecConfig      `yaml:"spec"`
}

type HTTPClientConfig struct {
	URL string `yaml:"url"`
}

type GenesisConfig struct {
	GenesisTime           time.Time   `yaml:"GENESIS_TIME"`
	GenesisValidatorsRoot common.Hash `yaml:"GENESIS_VALIDATORS_ROOT"`
}

type SpecConfig struct {
	SecondsPerSlot               uint64 `yaml:"SECONDS_PER_SLOT"`
	SlotsPerEpoch                uint64 `yaml:"SLOTS_PER_EPOCH"`
	AltairForkEpoch              uint64 `yaml:"ALTAIR_FORK_EPOCH"`
	AltairForkVersion            string `yaml:"ALTAIR_FORK_VERSION"`
	BellatrixForkEpoch           uint64 `yaml:"BELLATRIX_FORK_EPOCH"`
	BellatrixForkVersion         string `yaml:"BELLATRIX_FORK_VERSION"`
	EpochsPerSyncCommitteePeriod uint64 `yaml:"EPOCHS_PER_SYNC_COMMITTEE_PERIOD"`
	SyncCommitteeSize            int    `yaml:"SYNC_COMMITTEE_SIZE"`
	ValidatorRegistryLimit       int    `yaml:"VALIDATOR_REGISTRY_LIMIT"`
	HistoricalRootsLimit         int    `yaml:"HISTORICAL_ROOTS_LIMIT"`
	EpochsPerEth1VotingPeriod    uint64 `yaml:"EPOCHS_PER_ETH1_VOTING_PERIOD"`
}

func ReadFromFile(file string) (*Config, error) {
	f, err := os.OpenFile(file, os.O_RDONLY, os.ModePerm)
	if err != nil {
		return nil, fmt.Errorf("can't open config file: %w", err)
	}
	defer f.Close()
	dec := yaml.NewDecoder(f)
	dec.KnownFields(true)
	cfg := &Config{}
	if err = dec.Decode(cfg); err != nil {
		return nil, fmt.Errorf("can't decode yaml config: %w", err)
	}
	return cfg, nil
}
