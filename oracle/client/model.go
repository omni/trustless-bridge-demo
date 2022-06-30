package client

type ModelGenesis struct {
	Data ModelGenesisData `json:"data"`
}

type ModelGenesisData struct {
	GenesisTime           string `json:"genesis_time"`
	GenesisValidatorsRoot string `json:"genesis_validators_root"`
}

type ModelSpec struct {
	Data ModelSpecData `json:"data"`
}

type ModelSpecData struct {
	SecondsPerSlot               uint64 `json:"SECONDS_PER_SLOT,string"`
	SlotsPerEpoch                uint64 `json:"SLOTS_PER_EPOCH,string"`
	AltairForkEpoch              uint64 `json:"ALTAIR_FORK_EPOCH,string"`
	AltairForkVersion            string `json:"ALTAIR_FORK_VERSION"`
	BellatrixForkEpoch           uint64 `json:"BELLATRIX_FORK_EPOCH,string"`
	BellatrixForkVersion         string `json:"BELLATRIX_FORK_VERSION"`
	EpochsPerSyncCommitteePeriod uint64 `json:"EPOCHS_PER_SYNC_COMMITTEE_PERIOD,string"`
	SyncCommitteeSize            int    `json:"SYNC_COMMITTEE_SIZE,string"`
	ValidatorRegistryLimit       int    `json:"VALIDATOR_REGISTRY_LIMIT,string"`
	HistoricalRootsLimit         int    `json:"HISTORICAL_ROOTS_LIMIT,string"`
	EpochsPerEth1VotingPeriod    uint64 `json:"EPOCHS_PER_ETH1_VOTING_PERIOD,string"`
	SlotsPerHistoricalRoot       uint64 `json:"SLOTS_PER_HISTORICAL_ROOT,string"`
}
