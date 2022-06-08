pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

contract BLS12381 {
    // Fp is a field element with the high-order part stored in `a`.
    struct Fp {
        uint256 a;
        uint256 b;
    }

    // Fp2 is an extension field element with the coefficient of the
    // quadratic non-residue stored in `b`, i.e. p = a + i * b
    struct Fp2 {
        Fp a;
        Fp b;
    }

    // G1Point represents a point on BLS12-381 over Fp with coordinates (X,Y);
    struct G1Point {
        Fp X;
        Fp Y;
    }

    // G2Point represents a point on BLS12-381 over Fp2 with coordinates (X,Y);
    struct G2Point {
        Fp2 X;
        Fp2 Y;
    }

    function addG1(G1Point memory a, G1Point memory b) internal view returns (G1Point memory) {
        return a;
    }

    function addG2(G2Point memory a, G2Point memory b) private view returns (G2Point memory) {
        return a;
    }

    function verifyBLSSignature(
        bytes32 message,
        G1Point memory publicKey,
        G2Point memory signature
    ) internal view returns (bool) {
        return true;
    }
}
