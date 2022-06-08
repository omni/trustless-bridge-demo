package crypto

import (
	"github.com/ethereum/go-ethereum/common"
	"github.com/prysmaticlabs/prysm/crypto/bls/blst"
	blscommon "github.com/prysmaticlabs/prysm/crypto/bls/common"
)

func MustDecodePK(b []byte) blscommon.PublicKey {
	pk, err := blst.PublicKeyFromBytes(b)
	if err != nil {
		panic(err)
	}
	return pk
}

func MustDecodeSig(b []byte) blscommon.Signature {
	sig, err := blst.SignatureFromBytes(b)
	if err != nil {
		panic(err)
	}
	return sig
}

func Verify(hash common.Hash, domainRoot common.Hash, pk blscommon.PublicKey, sig blscommon.Signature) bool {
	root := Sha256Hash(hash.Bytes(), domainRoot.Bytes())
	return sig.Verify(pk, root[:])
}
