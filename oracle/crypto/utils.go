package crypto

import (
	"encoding/binary"

	"github.com/ethereum/go-ethereum/common"
)

func ZeroHash(n int) common.Hash {
	res := common.Hash{}
	for ; n > 1; n /= 2 {
		res = Sha256Hash(res.Bytes(), res.Bytes())
	}
	return res
}

func CeilPow2(n int) int {
	res := 1
	for res < n {
		res *= 2
	}
	return res
}

func UintToHash(v uint64) common.Hash {
	res := common.Hash{}
	binary.LittleEndian.PutUint64(res[:], v)
	return res
}

func BytesToChunks(s []byte) []common.Hash {
	chunks := make([]common.Hash, (len(s)+31)/32)
	for i := 0; i < len(s); i += 32 {
		res := common.Hash{}
		copy(res[:], s[i:])
		chunks[i/32] = res
	}
	return chunks
}
