package crypto

import (
	"fmt"

	"github.com/ethereum/go-ethereum/common"
)

type MerkleTree struct {
	isList bool
	length int
	limit  int
	leaves []common.Hash
}

type MerkleProof struct {
	genIndex int
	Path     []common.Hash
}

func NewVectorMerkleTree(leaves ...common.Hash) *MerkleTree {
	return &MerkleTree{
		isList: false,
		limit:  CeilPow2(len(leaves)),
		leaves: leaves,
	}
}

func NewListMerkleTree(leaves []common.Hash, limit int) *MerkleTree {
	if limit < len(leaves) {
		panic(fmt.Sprintf("invalid length, max %d, got %d", limit, len(leaves)))
	}
	if limit&(limit-1) > 0 {
		panic(fmt.Sprintf("limit is not a power of 2, %d", limit))
	}
	return &MerkleTree{
		isList: true,
		length: len(leaves),
		limit:  limit,
		leaves: leaves,
	}
}

func NewPackedVectorMerkleTree(data []byte) *MerkleTree {
	leaves := BytesToChunks(data)
	return &MerkleTree{
		isList: false,
		limit:  CeilPow2(len(leaves)),
		leaves: leaves,
	}
}

func NewPackedListMerkleTree(data []byte, length, limit int) *MerkleTree {
	leaves := BytesToChunks(data)
	return &MerkleTree{
		isList: true,
		length: length,
		limit:  limit,
		leaves: leaves,
	}
}

func (t *MerkleTree) Hash() common.Hash {
	x := merkle(t.leaves, t.limit)
	if t.isList {
		return Sha256Hash(x.Bytes(), UintToHash(uint64(t.length)).Bytes())
	}
	return x
}

func (t *MerkleTree) MakeProof(idx int) *MerkleProof {
	if idx < 0 || idx >= len(t.leaves) {
		panic("index out of bounds")
	}
	genIdx := idx + t.limit
	path := make([]common.Hash, 0, 10)

	l := idx
	r := l + 1
	for k := 1; genIdx > 1; k *= 2 {
		if genIdx%2 == 1 {
			l -= k
			e := r - k
			if e >= len(t.leaves) {
				e = len(t.leaves)
			}
			path = append(path, merkle(t.leaves[l:e], k))
		} else {
			r += k
			e := r
			if e >= len(t.leaves) {
				e = len(t.leaves)
			}
			if l+k <= e {
				path = append(path, merkle(t.leaves[l+k:e], k))
			} else {
				path = append(path, merkle(t.leaves[e:e], k))
			}
		}
		genIdx /= 2
	}
	if t.isList {
		return &MerkleProof{
			genIndex: idx + t.limit*2,
			Path:     append(path, UintToHash(uint64(t.length))),
		}
	}
	return &MerkleProof{
		genIndex: idx + t.limit,
		Path:     path,
	}
}

func (p *MerkleProof) ReconstructRoot(data common.Hash) common.Hash {
	genIndex := p.genIndex
	if genIndex>>len(p.Path) != 1 {
		panic("invalid proof length")
	}
	leaf := data
	for i := 0; genIndex > 1; i++ {
		if genIndex%2 == 1 {
			leaf = Sha256Hash(p.Path[i].Bytes(), leaf.Bytes())
		} else {
			leaf = Sha256Hash(leaf.Bytes(), p.Path[i].Bytes())
		}
		genIndex /= 2
	}
	return leaf
}

func HexToMerkleHash(s string) common.Hash {
	return BytesToMerkleHash(common.FromHex(s))
}

func BytesToMerkleHash(bs []byte) common.Hash {
	return NewVectorMerkleTree(BytesToChunks(bs)...).Hash()
}

func merkle(chunks []common.Hash, n int) common.Hash {
	if len(chunks) == 0 {
		return ZeroHash(n)
	}
	if n == 1 {
		return chunks[0]
	}
	m := n / 2
	if len(chunks) <= m {
		return Sha256Hash(merkle(chunks, m).Bytes(), ZeroHash(m).Bytes())
	}
	return Sha256Hash(merkle(chunks[:m], m).Bytes(), merkle(chunks[m:], m).Bytes())
}
