pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

library BLS12381 {
    uint8 constant MOD_EXP_PRECOMPILE_ADDRESS = 0x5;
    uint8 constant BLS12_381_G1_ADD_ADDRESS = 0x0a;
    uint8 constant BLS12_381_G2_ADD_ADDRESS = 0x0d;
    uint8 constant BLS12_381_PAIRING_PRECOMPILE_ADDRESS = 0x10;
    uint8 constant BLS12_381_MAP_FIELD_TO_CURVE_PRECOMPILE_ADDRESS = 0x12;
    string constant BLS_SIG_DST = "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_+";

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

    // G1PointCompressed represents a compressed version of G1Point
    // A  == (G1Point.B.a << 128) + G1Point.X.a
    // XB == G1Point.X.b
    // YB == G1Point.Y.b
    struct G1PointCompressed {
        uint256 A;
        uint256 XB;
        uint256 YB;
    }

    // G2Point represents a point on BLS12-381 over Fp2 with coordinates (X,Y);
    struct G2Point {
        Fp2 X;
        Fp2 Y;
    }

    function expandMessage(bytes32 message) private pure returns (bytes memory) {
        bytes32 b0 = sha256(abi.encodePacked(uint256(0), uint256(0), message, uint24(0x010000), BLS_SIG_DST));

        bytes memory output = new bytes(256);
        bytes32 chunk = sha256(abi.encodePacked(b0, uint8(0x01), BLS_SIG_DST));
        uint256 ptr;
        assembly {
            ptr := add(output, 0x20)
            mstore(ptr, chunk)
        }
        for (uint256 i = 2; i < 9; i++) {
            bytes32 input;
            assembly {
                input := xor(b0, mload(ptr))
            }
            ptr += 32;
            chunk = sha256(abi.encodePacked(input, uint8(i), BLS_SIG_DST));
            assembly {
                mstore(ptr, chunk)
            }
        }

        return output;
    }

    // Reduce the number encoded as the big-endian slice of data[start:end] modulo the BLS12-381 field modulus.
    // Copying of the base is cribbed from the following:
    // https://github.com/ethereum/solidity-examples/blob/f44fe3b3b4cca94afe9c2a2d5b7840ff0fafb72e/src/unsafe/Memory.sol#L57-L74
    function reduceModulo(bytes memory data, uint256 start, uint256 end) private view returns (bytes memory) {
        uint256 length = end - start;
        assert (length >= 0);
        assert (length <= data.length);

        bytes memory result = new bytes(48);

        bool success;
        assembly {
            let p := mload(0x40)
            // length of base
            mstore(p, length)
            // length of exponent
            mstore(add(p, 0x20), 0x20)
            // length of modulus
            mstore(add(p, 0x40), 48)
            // base
            // first, copy slice by chunks of EVM words
            let ctr := length
            let src := add(add(data, 0x20), start)
            let dst := add(p, 0x60)
            for { }
            or(gt(ctr, 0x20), eq(ctr, 0x20))
            { ctr := sub(ctr, 0x20) }
            {
                mstore(dst, mload(src))
                dst := add(dst, 0x20)
                src := add(src, 0x20)
            }
            // next, copy remaining bytes in last partial word
            let mask := sub(exp(256, sub(0x20, ctr)), 1)
            let srcpart := and(mload(src), not(mask))
            let destpart := and(mload(dst), mask)
            mstore(dst, or(destpart, srcpart))
            // exponent
            mstore(add(p, add(0x60, length)), 1)
            // modulus
            let modulusAddr := add(p, add(0x60, add(0x10, length)))
            mstore(modulusAddr, or(mload(modulusAddr), 0x1a0111ea397fe69a4b1ba7b6434bacd7)) // pt 1
            mstore(add(p, add(0x90, length)), 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab) // pt 2
            success := staticcall(
                gas(),
                MOD_EXP_PRECOMPILE_ADDRESS,
                p,
                add(0xB0, length),
                add(result, 0x20),
                48
            )
        }
        require(success, "call to modular exponentiation precompile failed");
        return result;
    }

    function convertSliceToFp(bytes memory data, uint256 start, uint256 end) private view returns (Fp memory) {
        bytes memory fieldElement = reduceModulo(data, start, end);
        uint256 a;
        uint256 b;
        assembly {
            a := mload(add(fieldElement, 32))
            b := mload(add(fieldElement, 48))
        }
        return Fp(a >> 128, b);
    }

    function hashToField(bytes32 message) private view returns (Fp2[2] memory result) {
        bytes memory some_bytes = expandMessage(message);
        result[0] = Fp2(
            convertSliceToFp(some_bytes, 0, 64),
            convertSliceToFp(some_bytes, 64, 128)
        );
        result[1] = Fp2(
            convertSliceToFp(some_bytes, 128, 192),
            convertSliceToFp(some_bytes, 192, 256)
        );
    }

    function mapToCurve(Fp2 memory fieldElement) private view returns (G2Point memory result) {
        uint256[8] memory input;
        input[0] = fieldElement.a.a;
        input[1] = fieldElement.a.b;
        input[2] = fieldElement.b.a;
        input[3] = fieldElement.b.b;

        bool success;
        assembly {
            success := staticcall(
                gas(),
                BLS12_381_MAP_FIELD_TO_CURVE_PRECOMPILE_ADDRESS,
                input,
                128,
                input,
                256
            )
        }
        require(success, "call to map to curve precompile failed");

        return G2Point(
            Fp2(
                Fp(input[0], input[1]),
                Fp(input[2], input[3])
            ),
            Fp2(
                Fp(input[4], input[5]),
                Fp(input[6], input[7])
            )
        );
    }

    function addG1(G1Point memory a, G1PointCompressed memory b) internal view returns (G1Point memory result) {
        uint256[8] memory input;
        input[0]  = a.X.a;
        input[1]  = a.X.b;
        input[2]  = a.Y.a;
        input[3]  = a.Y.b;

        input[4]  = b.A & 0xffffffffffffffffffffffffffffffff;
        input[5]  = b.XB;
        input[6]  = b.A >> 128;
        input[7]  = b.YB;

        bool success;
        assembly {
            success := staticcall(
                gas(),
                BLS12_381_G1_ADD_ADDRESS,
                input,
                256,
                input,
                128
            )
        }
        require(success, "call to addition in G1 precompile failed");

        return G1Point(
            Fp(input[0], input[1]),
            Fp(input[2], input[3])
        );
    }

    function addG2(G2Point memory a, G2Point memory b) private view returns (G2Point memory) {
        uint256[16] memory input;
        input[0]  = a.X.a.a;
        input[1]  = a.X.a.b;
        input[2]  = a.X.b.a;
        input[3]  = a.X.b.b;
        input[4]  = a.Y.a.a;
        input[5]  = a.Y.a.b;
        input[6]  = a.Y.b.a;
        input[7]  = a.Y.b.b;

        input[8]  = b.X.a.a;
        input[9]  = b.X.a.b;
        input[10] = b.X.b.a;
        input[11] = b.X.b.b;
        input[12] = b.Y.a.a;
        input[13] = b.Y.a.b;
        input[14] = b.Y.b.a;
        input[15] = b.Y.b.b;

        bool success;
        assembly {
            success := staticcall(
                gas(),
                BLS12_381_G2_ADD_ADDRESS,
                input,
                512,
                input,
                256
            )
        }
        require(success, "call to addition in G2 precompile failed");

        return G2Point(
            Fp2(
                Fp(input[0], input[1]),
                Fp(input[2], input[3])
            ),
            Fp2(
                Fp(input[4], input[5]),
                Fp(input[6], input[7])
            )
        );
    }

    // Implements "hash to the curve" from the IETF BLS draft.
    function hashToCurve(bytes32 message) private view returns (G2Point memory) {
        Fp2[2] memory messageElementsInField = hashToField(message);
        G2Point memory firstPoint = mapToCurve(messageElementsInField[0]);
        G2Point memory secondPoint = mapToCurve(messageElementsInField[1]);
        return addG2(firstPoint, secondPoint);
    }

    function blsPairingCheck(G1Point memory publicKey, G2Point memory messageOnCurve, G2Point memory signature) private view returns (bool) {
        uint256[24] memory input;

        input[0] =  publicKey.X.a;
        input[1] =  publicKey.X.b;
        input[2] =  publicKey.Y.a;
        input[3] =  publicKey.Y.b;

        input[4] =  messageOnCurve.X.a.a;
        input[5] =  messageOnCurve.X.a.b;
        input[6] =  messageOnCurve.X.b.a;
        input[7] =  messageOnCurve.X.b.b;
        input[8] =  messageOnCurve.Y.a.a;
        input[9] =  messageOnCurve.Y.a.b;
        input[10] = messageOnCurve.Y.b.a;
        input[11] = messageOnCurve.Y.b.b;

        // NOTE: this constant is -P1, where P1 is the generator of the group G1.
        input[12] = 31827880280837800241567138048534752271;
        input[13] = 88385725958748408079899006800036250932223001591707578097800747617502997169851;
        input[14] = 22997279242622214937712647648895181298;
        input[15] = 46816884707101390882112958134453447585552332943769894357249934112654335001290;

        input[16] =  signature.X.a.a;
        input[17] =  signature.X.a.b;
        input[18] =  signature.X.b.a;
        input[19] =  signature.X.b.b;
        input[20] =  signature.Y.a.a;
        input[21] =  signature.Y.a.b;
        input[22] =  signature.Y.b.a;
        input[23] =  signature.Y.b.b;

        bool success;
        assembly {
            success := staticcall(
                gas(),
                BLS12_381_PAIRING_PRECOMPILE_ADDRESS,
                input,
                768,
                input,
                32
            )
        }
        require(success, "call to pairing precompile failed");

        return input[0] == 1;
    }

    function verifyBLSSignature(
        bytes32 message,
        G1Point memory publicKey,
        G2Point memory signature
    ) internal view returns (bool) {
        G2Point memory messageOnCurve = hashToCurve(message);

        return blsPairingCheck(publicKey, messageOnCurve, signature);
    }
}
