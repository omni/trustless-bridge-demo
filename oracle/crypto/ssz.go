package crypto

import (
	"encoding/binary"
	"fmt"

	"github.com/ethereum/go-ethereum/common"
	ethpb2 "github.com/prysmaticlabs/prysm/proto/prysm/v1alpha1"
)

func MustHashTreeRoot(data interface{ HashTreeRoot() ([32]byte, error) }) common.Hash {
	hash, err := data.HashTreeRoot()
	if err != nil {
		panic(fmt.Errorf("failed to calculate hash tree root: %w", err))
	}
	return common.BytesToHash(hash[:])
}

func HashRootsVector(rs [][]byte) common.Hash {
	chunks := make([]common.Hash, len(rs))
	for i, r := range rs {
		chunks[i] = common.BytesToHash(r)
	}
	return NewVectorMerkleTree(chunks...).Hash()
}

func HashRootsList(rs [][]byte, limit int) common.Hash {
	chunks := make([]common.Hash, len(rs))
	for i, r := range rs {
		chunks[i] = common.BytesToHash(r)
	}
	return NewListMerkleTree(chunks, limit).Hash()
}

func HashEth1Datas(ds []*ethpb2.Eth1Data, limit int) common.Hash {
	chunks := make([]common.Hash, len(ds))
	for i, d := range ds {
		chunks[i] = MustHashTreeRoot(d)
	}
	return NewListMerkleTree(chunks, limit).Hash()
}

func HashValidators(vs []*ethpb2.Validator, limit int) common.Hash {
	chunks := make([]common.Hash, len(vs))
	for i, v := range vs {
		chunks[i] = MustHashTreeRoot(v)
	}
	return NewListMerkleTree(chunks, limit).Hash()
}

func HashUint64List(vs []uint64, limit int) common.Hash {
	data := make([]byte, 8*len(vs))
	for i, x := range vs {
		binary.LittleEndian.PutUint64(data[i*8:], x)
	}
	return NewPackedListMerkleTree(data, len(vs), limit/4).Hash()
}

func HashUint64Vector(vs []uint64) common.Hash {
	data := make([]byte, 8*len(vs))
	for i, x := range vs {
		binary.LittleEndian.PutUint64(data[i*8:], x)
	}
	return NewPackedVectorMerkleTree(data).Hash()
}

func HashUint8List(vs []byte, limit int) common.Hash {
	return NewPackedListMerkleTree(vs, len(vs), limit/32).Hash()
}
