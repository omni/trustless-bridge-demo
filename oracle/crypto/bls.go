package crypto

import (
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/prysmaticlabs/prysm/crypto/bls/blst"
	blscommon "github.com/prysmaticlabs/prysm/crypto/bls/common"
	blstbind "github.com/supranational/blst/bindings/go"
)

type Fp struct {
	A *big.Int `json:"a,string"`
	B *big.Int `json:"b,string"`
}

type G1Point struct {
	raw blscommon.PublicKey
	X   Fp `json:"X"`
	Y   Fp `json:"Y"`
}

type Fp2 struct {
	A Fp `json:"a"`
	B Fp `json:"b"`
}

type G2Point struct {
	raw blscommon.Signature
	X   Fp2 `json:"X"`
	Y   Fp2 `json:"Y"`
}

func (p *G1Point) String() string {
	return hexutil.Encode(p.raw.Marshal())
}

func MustDecodePK(b []byte) G1Point {
	pk, err := blst.PublicKeyFromBytes(b)
	if err != nil {
		panic(err)
	}
	return PkToG1(pk)
}

func MustDecodeSig(b []byte) G2Point {
	sig, err := blst.SignatureFromBytes(b)
	if err != nil {
		panic(err)
	}
	return SigToG2(sig)
}

func Verify(hash common.Hash, domainRoot common.Hash, pk G1Point, sig G2Point) bool {
	root := Sha256Hash(hash.Bytes(), domainRoot.Bytes())
	return sig.raw.Verify(pk.raw, root[:])
}

func AddG1Points(a, b *G1Point) *G1Point {
	if a == nil {
		return b
	}
	x := PkToG1(a.raw.Aggregate(b.raw))
	return &x
}

func PkToG1(pk blscommon.PublicKey) G1Point {
	b := new(blstbind.P1Affine).Uncompress(pk.Marshal()).Serialize()
	return G1Point{
		raw: pk,
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
		raw: sig,
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
