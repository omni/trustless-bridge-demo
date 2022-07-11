pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

import "../libraries/BLS12381.sol";
import "./BeaconLightClientConfig.sol";

contract BeaconLightClientCryptoUtils is BeaconLightClientConfig {
    function _aggregateMissingPubkeys(
        BLS12381.G1PointCompressed[] memory pks,
        BLS12381.G1Point memory aggregatedPK,
        bytes32[SYNC_COMMITTEE_BIT_LIST_WORDS_SIZE] memory aggregationBitList
    ) internal view returns (uint256[] memory, bytes32[] memory, BLS12381.G1Point memory) {
        BLS12381.G1Point memory result = aggregatedPK;
        uint256 count = 0;
        uint256 word = 0;
        uint256[] memory indices = new uint256[](pks.length);
        bytes32[] memory leaves = new bytes32[](pks.length);
        for (uint256 i = SYNC_COMMITTEE_SIZE * 2 - 1; i >= SYNC_COMMITTEE_SIZE; i--) {
            uint256 m = i & 0xff;
            if (m == 0xff) {
                word = uint256(aggregationBitList[(i >> 8) - 2]);
            }
            if (word & (1 << m) == 0) {
                result = BLS12381.addG1(result, pks[count]);
                indices[count] = i;
                leaves[count] = _hashG1Compressed(pks[count]);
                count++;
            }
        }
        require(count == pks.length, "Invalid number of missed sync committee members");
        return (indices, leaves, result);
    }

    function _hashG1(BLS12381.G1Point memory point) internal view returns (bytes32 c) {
        uint256 a = point.Y.a;
        uint256 b = point.Y.b;
        if (a > 0x0d0088f51cbff34d258dd3db21a5d66b || a == 0x0d0088f51cbff34d258dd3db21a5d66b && b > 0xb23ba5c279c2895fb39869507b587b120f55ffff58a9ffffdcff7fffffffd555) {
            a = point.X.a | 0xa0000000000000000000000000000000;
        } else {
            a = point.X.a | 0x80000000000000000000000000000000;
        }
        assembly {
            mstore(0x00, shl(128, a))
            mstore(0x20, 0)
            mstore(0x10, mload(add(mload(point), 0x20)))
            let status := staticcall(gas(), 0x02, 0x00, 0x40, 0x00, 0x20)
            if iszero(status) {
                revert(0, 0)
            }
            c := mload(0x00)
        }
    }

    function _hashG1Compressed(BLS12381.G1PointCompressed memory point) internal view returns (bytes32 c) {
        uint256 a = point.A >> 128;
        uint256 b = point.YB;
        if (a > 0x0d0088f51cbff34d258dd3db21a5d66b || a == 0x0d0088f51cbff34d258dd3db21a5d66b && b > 0xb23ba5c279c2895fb39869507b587b120f55ffff58a9ffffdcff7fffffffd555) {
            a = point.A | 0xa0000000000000000000000000000000;
        } else {
            a = point.A | 0x80000000000000000000000000000000;
        }
        assembly {
            mstore(0x00, shl(128, a))
            mstore(0x20, 0)
            mstore(0x10, mload(add(point, 0x20)))
            let status := staticcall(gas(), 0x02, 0x00, 0x40, 0x00, 0x20)
            if iszero(status) {
                revert(0, 0)
            }
            c := mload(0x00)
        }
    }
}
