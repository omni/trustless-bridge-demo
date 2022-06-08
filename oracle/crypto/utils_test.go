package crypto

import (
	"crypto/sha256"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/stretchr/testify/assert"
)

func TestSha256(t *testing.T) {
	b1 := common.Hash{0, 1, 2}
	b2 := common.Hash{3, 4, 5}
	b3 := append(b1[:], b2[:]...)
	exp := common.Hash(sha256.Sum256(b3))
	assert.Equal(t, exp, Sha256Hash(b1.Bytes(), b2.Bytes()))
}
