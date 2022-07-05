pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

import "../libraries/BLS12381.sol";
import "./BeaconLightClientConfig.sol";

contract BeaconLightClientCryptoUtils is BeaconLightClientConfig {
    function _aggregateRemainingPubkeys(
        BLS12381.G1PointCompressed[SYNC_COMMITTEE_SIZE] memory pks,
        BLS12381.G1Point memory aggregatedPK,
        bytes32[SYNC_COMMITTEE_BIT_LIST_WORDS_SIZE] memory aggregationBitList
    ) internal returns (uint256, BLS12381.G1Point memory) {
        BLS12381.G1Point memory result = aggregatedPK;
        uint256 count = SYNC_COMMITTEE_SIZE;
        uint256 word = 0;
        for (uint256 i = 0; i < SYNC_COMMITTEE_SIZE; i++) {
            uint256 m = i & 0xff;
            if (m == 0) {
                word = uint256(aggregationBitList[i >> 8]);
            }
            if (word & (1 << m) == 0) {
                result = BLS12381.addG1(result, pks[i]);
                count--;
            }
        }
        return (count, result);
    }

    function _hashSyncCommittee(
        BLS12381.G1PointCompressed[SYNC_COMMITTEE_SIZE] memory syncCommittee,
        BLS12381.G1Point memory aggregatedPK
    ) internal returns (bytes32) {
        bytes32[SYNC_COMMITTEE_BRANCH_SIZE] memory branch;
        for (uint256 i = 0; i < SYNC_COMMITTEE_SIZE; i++) {
            bytes32 hash = _hashG1Compressed(syncCommittee[i]);
            uint256 k = 0;
            while (i & (1 << k) > 0) {
                hash = sha256(abi.encodePacked(branch[k], hash));
                k++;
            }
            branch[k] = hash;
        }
        return sha256(abi.encodePacked(branch[SYNC_COMMITTEE_BRANCH_SIZE - 1], _hashG1(aggregatedPK)));
    }

    function _hashG1(BLS12381.G1Point memory point) internal returns (bytes32) {
        uint256 a = point.Y.a;
        uint256 b = point.Y.b;
        if (a > 0x0d0088f51cbff34d258dd3db21a5d66b || a == 0x0d0088f51cbff34d258dd3db21a5d66b && b > 0xb23ba5c279c2895fb39869507b587b120f55ffff58a9ffffdcff7fffffffd555) {
            a = point.X.a | 0xa0000000000000000000000000000000;
        } else {
            a = point.X.a | 0x80000000000000000000000000000000;
        }
        return sha256(abi.encodePacked(uint128(a), point.X.b, uint128(0)));
    }

    function _hashG1Compressed(BLS12381.G1PointCompressed memory point) internal returns (bytes32) {
        uint256 a = point.A >> 128;
        uint256 b = point.YB;
        if (a > 0x0d0088f51cbff34d258dd3db21a5d66b || a == 0x0d0088f51cbff34d258dd3db21a5d66b && b > 0xb23ba5c279c2895fb39869507b587b120f55ffff58a9ffffdcff7fffffffd555) {
            a = point.A | 0xa0000000000000000000000000000000;
        } else {
            a = point.A | 0x80000000000000000000000000000000;
        }
        return sha256(abi.encodePacked(uint128(a), point.XB, uint128(0)));
    }
}
