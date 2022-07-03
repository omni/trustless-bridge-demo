package crypto

import (
	"crypto/sha256"

	"github.com/ethereum/go-ethereum/common"
)

func Sha256Hash(bs ...[]byte) common.Hash {
	h := sha256.New()
	h.Reset()
	for _, b := range bs {
		h.Write(b)
	}
	res := common.Hash{}
	h.Sum(res[:0:32])
	return res
}
