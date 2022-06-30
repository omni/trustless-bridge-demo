package lightclient

import (
	"encoding/binary"
	"log"

	"bls-sandbox/crypto"

	"github.com/ethereum/go-ethereum/common"
	blscommon "github.com/prysmaticlabs/prysm/crypto/bls/common"
	ethpb2 "github.com/prysmaticlabs/prysm/proto/prysm/v1alpha1"
)

func MustHashTreeRoot(data interface{ HashTreeRoot() ([32]byte, error) }) common.Hash {
	hash, err := data.HashTreeRoot()
	if err != nil {
		log.Fatalln("failed to calculate hash tree root", err)
	}
	return common.BytesToHash(hash[:])
}

func ConvertToSyncCommittee(cm *ethpb2.SyncCommittee) *SyncCommittee {
	committee := &SyncCommittee{
		PublicKeys:   make([]blscommon.PublicKey, len(cm.Pubkeys)),
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
		BodyRoot:      MustHashTreeRoot(block.Body),
	}
}

func hashRootsVector(rs [][]byte) common.Hash {
	chunks := make([]common.Hash, len(rs))
	for i, r := range rs {
		chunks[i] = common.BytesToHash(r)
	}
	return crypto.NewVectorMerkleTree(chunks...).Hash()
}

func hashRootsList(rs [][]byte, limit int) common.Hash {
	chunks := make([]common.Hash, len(rs))
	for i, r := range rs {
		chunks[i] = common.BytesToHash(r)
	}
	return crypto.NewListMerkleTree(chunks, limit).Hash()
}

func hashEth1Datas(ds []*ethpb2.Eth1Data, limit int) common.Hash {
	chunks := make([]common.Hash, len(ds))
	for i, d := range ds {
		chunks[i] = MustHashTreeRoot(d)
	}
	return crypto.NewListMerkleTree(chunks, limit).Hash()
}

func hashValidators(vs []*ethpb2.Validator, limit int) common.Hash {
	chunks := make([]common.Hash, len(vs))
	for i, v := range vs {
		chunks[i] = MustHashTreeRoot(v)
	}
	return crypto.NewListMerkleTree(chunks, limit).Hash()
}

func hashUint64List(vs []uint64, limit int) common.Hash {
	data := make([]byte, 8*len(vs))
	for i, x := range vs {
		binary.LittleEndian.PutUint64(data[i*8:], x)
	}
	return crypto.NewPackedListMerkleTree(data, len(vs), limit/4).Hash()
}

func hashUint64Vector(vs []uint64) common.Hash {
	data := make([]byte, 8*len(vs))
	for i, x := range vs {
		binary.LittleEndian.PutUint64(data[i*8:], x)
	}
	return crypto.NewPackedVectorMerkleTree(data).Hash()
}

func hashUint8List(vs []byte, limit int) common.Hash {
	return crypto.NewPackedListMerkleTree(vs, len(vs), limit/32).Hash()
}
