package lightclient

import (
	"github.com/ethereum/go-ethereum/common"
	ethpb2 "github.com/prysmaticlabs/prysm/proto/prysm/v1alpha1"

	"oracle/crypto"
)

type BeaconBlockHeader struct {
	Slot          uint64      `json:"slot" abi:"slot"`
	ProposerIndex uint64      `json:"proposerIndex" abi:"proposerIndex"`
	ParentRoot    common.Hash `json:"parentRoot" abi:"parentRoot"`
	StateRoot     common.Hash `json:"stateRoot" abi:"stateRoot"`
	BodyRoot      common.Hash `json:"bodyRoot" abi:"bodyRoot"`
}

type Update struct {
	ForkVersion             [4]byte           `json:"forkVersion" abi:"forkVersion"`
	SignatureSlot           uint64            `json:"signatureSlot" abi:"signatureSlot"`
	AttestedHeader          BeaconBlockHeader `json:"attestedHeader" abi:"attestedHeader"`
	FinalizedHeader         BeaconBlockHeader `json:"finalizedHeader" abi:"finalizedHeader"`
	SyncCommittee           []crypto.G1Point  `json:"syncCommittee" abi:"syncCommittee"`
	SyncCommitteeAggregated crypto.G1Point    `json:"syncCommitteeAggregated" abi:"syncCommitteeAggregated"`
	SyncAggregateSignature  crypto.G2Point    `json:"syncAggregateSignature" abi:"syncAggregateSignature"`
	SyncAggregateBitList    []common.Hash     `json:"syncAggregateBitList" abi:"syncAggregateBitList"`
	SyncCommitteeBranch     []common.Hash     `json:"syncCommitteeBranch" abi:"syncCommitteeBranch"`
	FinalityBranch          []common.Hash     `json:"finalityBranch" abi:"finalityBranch"`
}

type SyncCommittee struct {
	PublicKeys   []crypto.G1Point
	AggregateKey crypto.G1Point
}

func ConvertToSyncCommittee(cm *ethpb2.SyncCommittee) *SyncCommittee {
	committee := &SyncCommittee{
		PublicKeys:   make([]crypto.G1Point, len(cm.Pubkeys)),
		AggregateKey: crypto.MustDecodePK(cm.AggregatePubkey),
	}
	for i, pk := range cm.Pubkeys {
		committee.PublicKeys[i] = crypto.MustDecodePK(pk)
	}
	return committee
}

func ConvertToHeader(block *ethpb2.BeaconBlockBellatrix) BeaconBlockHeader {
	return BeaconBlockHeader{
		Slot:          uint64(block.Slot),
		ProposerIndex: uint64(block.ProposerIndex),
		ParentRoot:    common.BytesToHash(block.ParentRoot),
		StateRoot:     common.BytesToHash(block.StateRoot),
		BodyRoot:      crypto.MustHashTreeRoot(block.Body),
	}
}
