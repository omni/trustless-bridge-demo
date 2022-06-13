package lightclient

import (
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	blscommon "github.com/prysmaticlabs/prysm/crypto/bls/common"
	blstbind "github.com/supranational/blst/bindings/go"
)

type Fp struct {
	A *big.Int `json:"a,string"`
	B *big.Int `json:"b,string"`
}

type G1Point struct {
	X Fp
	Y Fp
}

type Fp2 struct {
	A Fp `json:"a"`
	B Fp `json:"b"`
}

type G2Point struct {
	X Fp2
	Y Fp2
}

type BeaconBlockHeader struct {
	Slot                 uint64      `json:"slot" abi:"slot"`
	ProposerIndex        uint64      `json:"proposerIndex" abi:"proposerIndex"`
	ParentRoot           common.Hash `json:"parentRoot" abi:"parentRoot"`
	StateRoot            common.Hash `json:"stateRoot" abi:"stateRoot"`
	BodyRoot             common.Hash `json:"bodyRoot" abi:"bodyRoot"`
	ExecutionStateRoot   common.Hash `json:"executionStateRoot" abi:"executionStateRoot"`
	ExecutionBlockNumber uint64      `json:"executionBlockNumber" abi:"executionBlockNumber"`
}

type Update struct {
	ForkVersion                [4]byte           `json:"forkVersion" abi:"forkVersion"`
	AttestedHeader             BeaconBlockHeader `json:"attestedHeader" abi:"attestedHeader"`
	FinalizedHeader            BeaconBlockHeader `json:"finalizedHeader" abi:"finalizedHeader"`
	SyncCommittee              []G1Point         `json:"syncCommittee" abi:"syncCommittee"`
	SyncCommitteeAggregated    G1Point           `json:"syncCommitteeAggregated" abi:"syncCommitteeAggregated"`
	SyncAggregateSignature     G2Point           `json:"syncAggregateSignature" abi:"syncAggregateSignature"`
	SyncAggregateBitList       []common.Hash     `json:"syncAggregateBitList" abi:"syncAggregateBitList"`
	SyncCommitteeBranch        []common.Hash     `json:"syncCommitteeBranch" abi:"syncCommitteeBranch"`
	FinalityBranch             []common.Hash     `json:"finalityBranch" abi:"finalityBranch"`
	ExecutionPayloadBranch     []common.Hash     `json:"executionPayloadBranch" abi:"executionPayloadBranch"`
	ExecutionStateRootBranch   []common.Hash     `json:"executionStateRootBranch" abi:"executionStateRootBranch"`
	ExecutionBlockNumberBranch []common.Hash     `json:"executionBlockNumberBranch" abi:"executionBlockNumberBranch"`
}

type SyncCommittee struct {
	PublicKeys   []blscommon.PublicKey
	AggregateKey blscommon.PublicKey
}

func PkToG1(pk blscommon.PublicKey) G1Point {
	b := new(blstbind.P1Affine).Uncompress(pk.Marshal()).Serialize()
	return G1Point{
		X: Fp{
			A: big.NewInt(0).SetBytes(b[0:16]),
			B: big.NewInt(0).SetBytes(b[16:48]),
		},
		Y: Fp{
			A: big.NewInt(0).SetBytes(b[48:64]),
			B: big.NewInt(0).SetBytes(b[64:96]),
		},
	}
}

func SigToG2(sig blscommon.Signature) G2Point {
	b := new(blstbind.P2Affine).Uncompress(sig.Marshal()).Serialize()
	return G2Point{
		X: Fp2{
			B: Fp{
				A: big.NewInt(0).SetBytes(b[0:16]),
				B: big.NewInt(0).SetBytes(b[16:48]),
			},
			A: Fp{
				A: big.NewInt(0).SetBytes(b[48:64]),
				B: big.NewInt(0).SetBytes(b[64:96]),
			},
		},
		Y: Fp2{
			B: Fp{
				A: big.NewInt(0).SetBytes(b[96+0 : 96+16]),
				B: big.NewInt(0).SetBytes(b[96+16 : 96+48]),
			},
			A: Fp{
				A: big.NewInt(0).SetBytes(b[96+48 : 96+64]),
				B: big.NewInt(0).SetBytes(b[96+64 : 96+96]),
			},
		},
	}
}
