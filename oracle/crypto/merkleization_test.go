package crypto

import (
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/stretchr/testify/assert"
)

func TestMerkleRoot(t *testing.T) {
	res := NewVectorMerkleTree(UintToHash(1), UintToHash(2), UintToHash(3), UintToHash(4), UintToHash(5))
	expected := Sha256Hash(
		Sha256Hash(
			Sha256Hash(common.Hash{1}.Bytes(), common.Hash{2}.Bytes()).Bytes(),
			Sha256Hash(common.Hash{3}.Bytes(), common.Hash{4}.Bytes()).Bytes(),
		).Bytes(),
		Sha256Hash(
			Sha256Hash(common.Hash{5}.Bytes(), common.Hash{}.Bytes()).Bytes(),
			Sha256Hash(common.Hash{}.Bytes(), common.Hash{}.Bytes()).Bytes(),
		).Bytes(),
	)
	assert.Equal(t, expected, res.Hash())
}

func TestSimpleMerkleRoot(t *testing.T) {
	assert.Equal(t, common.Hash{}, NewVectorMerkleTree(UintToHash(0)).Hash())
	assert.Equal(t, common.Hash{1}, NewVectorMerkleTree(UintToHash(1)).Hash())
	assert.Equal(t,
		Sha256Hash(common.Hash{1}.Bytes(), common.Hash{2}.Bytes()),
		NewVectorMerkleTree(UintToHash(1), UintToHash(2)).Hash(),
	)
}

func TestMerkleMultiProof(t *testing.T) {
	leaves := make([]common.Hash, 512)
	for i := range leaves {
		leaves[i] = UintToHash(uint64(i + 1))
	}
	tree := NewVectorMerkleTree(leaves...)

	proof := tree.MakeMultiProof([]int{3, 7, 15, 16, 17, 35, 87, 123, 124, 156, 199, 417, 483, 511})
	assert.Equal(t, tree.Hash(), proof.ReconstructRoot())

	proof = tree.MakeMultiProof([]int{17})
	assert.Equal(t, tree.Hash(), proof.ReconstructRoot())

	proof = tree.MakeMultiProof(nil)
	assert.Equal(t, tree.Hash(), proof.ReconstructRoot())
}
