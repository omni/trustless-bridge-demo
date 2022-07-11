pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "../contracts/light_client/libraries/BLS12381.sol";
import "../contracts/light_client/libraries/Merkle.sol";
import "../contracts/light_client/utils/BeaconLightClientCryptoUtils.sol";

contract MultiProofTest is Test {
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

    function _aggregateMissingPubkeys(
        BLS12381.G1PointCompressed[] memory pks,
        BLS12381.G1Point memory aggregatedPK,
        bytes32[2] memory aggregationBitList
    ) internal view returns (uint256[] memory, bytes32[] memory, BLS12381.G1Point memory) {
        BLS12381.G1Point memory result = aggregatedPK;
        uint256 count = 0;
        uint256 word = 0;
        uint256[] memory indices = new uint256[](pks.length);
        bytes32[] memory leaves = new bytes32[](pks.length);
        for (uint256 i = 512 * 2 - 1; i >= 512; i--) {
            uint256 m = i & 0xff;
            if (m == 0xff) {
                word = uint256(aggregationBitList[(i >> 8) - 2]);
            }
            if (word & (1 << m) == 0) {
                // TODO does not work in anvil, since precompiles are missing
                result = BLS12381.addG1(result, pks[count]);
                indices[count] = i;
                leaves[count] = _hashG1Compressed(pks[count]);
                count++;
            }
        }
        require(count == pks.length, "Invalid number of missed sync committee members");
        return (indices, leaves, result);
    }

    function testMultiProofVerification() public {
        BLS12381.G1PointCompressed[] memory missedSyncCommitteeParticipants = new BLS12381.G1PointCompressed[](4);
        missedSyncCommitteeParticipants[3] = BLS12381.G1PointCompressed(1322963447518326641402564965125844083445565229145492590851857911084748630199, 75099807607762601448930695436327644885318045693024392524169130549367236271635, 39535846746090197049321507320505585759763310865320480128302544829737445378937);
        missedSyncCommitteeParticipants[2] = BLS12381.G1PointCompressed(227997503023363890773671051016183103067068524393821754724004375202874960680, 71771144661331953687023783894789160895189361927274962294550236258572709610218, 14685159746053901024770077184657703519479500955079748928683282988421544007298);
        missedSyncCommitteeParticipants[1] = BLS12381.G1PointCompressed(10854255308361297111712679189107013957729543009708665441058240905029869816216, 49393360971827907258066995864114107640371946184186786020170493528767525221367, 97121523656564515441334814169719908007441244787981261705940323433662188291774);
        missedSyncCommitteeParticipants[0] = BLS12381.G1PointCompressed(3099086782601141871227334869665705102345280470252681476921595368702280354869, 51844678223995582268634046157364014296483461136400090453066014072712151551195, 68682716656385879705631836151029743981143034262187657643975094846677840984449);
        BLS12381.G1Point memory syncAggregatePubkey = BLS12381.G1Point(
            BLS12381.Fp(11318883171785626549970765727483389694, 2705798477144109178661335813076841765819843637166312312823820274454070004757),
            BLS12381.Fp(33240055057450239304985046771198158153, 46582869687762708906581491617199583704010921180325469204116699806874493652942)
        );
        bytes32[2] memory syncAggregateBitList;
        syncAggregateBitList[0] = 0xffffffffffffffff7fffffffffdffffffffffeffffffffffffffffffffffffff;
        syncAggregateBitList[1] = 0xffffffffffffffffefffffffffffffffffffffffffffffffffffffffffffffff;
        (uint256[] memory indices, bytes32[] memory leaves, BLS12381.G1Point memory aggregatedPK) = _aggregateMissingPubkeys(
            missedSyncCommitteeParticipants,
            syncAggregatePubkey,
            syncAggregateBitList
        );
        assertEq(indices.length, 4);
        assertEq(leaves.length, 4);
        assertEq(indices[0], 956);
        assertEq(indices[1], 703);
        assertEq(indices[2], 661);
        assertEq(indices[3], 616);
        assertEq(leaves[0], 0xa1f377b7c1d1cbb4f527ec9ab69dc366e1431d1cc0f00b3380c13f31503ce7ab);
        assertEq(leaves[1], 0x016edb11c922448f3def15266021bf9a917718dd49719ee1d81ddcdc94832e04);
        assertEq(leaves[2], 0x0d71e43ce28777f0d52640dddb7190a232f28d733c7bb46465f31c2a8467b7b9);
        assertEq(leaves[3], 0xb685c78ea9d171b67e47123622aeb890692e7bf4d3f6ea508d70c58b38c3e273);

        bytes32[] memory syncCommitteeRootDecommitments = new bytes32[](26);
        syncCommitteeRootDecommitments[0] = 0xc19425014a59b994f14b8988d5564dc81bc89bcfb2013382373f5c96ac168857;
        syncCommitteeRootDecommitments[1] = 0x3eb430f3abdb50bc86914eb60ccf1a86166a2a7a838bdd29fb1771d143b781f2;
        syncCommitteeRootDecommitments[2] = 0xf7f9476ea2f43b5996c6be368425443aaa8b82728c0daaf878124842a0a97242;
        syncCommitteeRootDecommitments[3] = 0x8ec39381cb84b10aece312bb9ad0a2379c711d54b493b3714eb7cbbd53746c81;
        syncCommitteeRootDecommitments[4] = 0x0c0bdfa107bb166710666e0c7ada6ad7e3046c358b1be3f44f0f4c49eca1e47d;
        syncCommitteeRootDecommitments[5] = 0x0436e657caeeea2537d96e0854c3d9f73491ddf0a41568058e047fd36fdc4328;
        syncCommitteeRootDecommitments[6] = 0x2ef9ec03fe0893b33e4b9b90045c05f8e1b6e3bef23d5fc098f8f279f381e8cf;
        syncCommitteeRootDecommitments[7] = 0x8c30e8a3273dd73c6000bfe92ae817f17b7bcb701a15906966b2ecc8a4242580;
        syncCommitteeRootDecommitments[8] = 0x0e0c7edeba7fa34164bc4cd8dc4dd9da1fd8205a6c03a8b679b081659c18a670;
        syncCommitteeRootDecommitments[9] = 0x85c10376396ed4ca3312f177462506b01c2a5f48366d3c405f46ffa0e66fd949;
        syncCommitteeRootDecommitments[10] = 0x220d14d719daa388b8f13570361566deb5f2db5fc34cbd7cd9a32342622ea981;
        syncCommitteeRootDecommitments[11] = 0xd103ad5f2b39842126e6e64edeaaa8b414ee37ec8f04c7ee35b8e7845806d106;
        syncCommitteeRootDecommitments[12] = 0x95b60144851e5ad32c83f195f7448faef2c78d0ea8668941b3fde791ac42364b;
        syncCommitteeRootDecommitments[13] = 0x706e131ae76b04c58ef26e7aa2ba5507ebe1bc3cf763e20ea30b84112554c2d0;
        syncCommitteeRootDecommitments[14] = 0xd498c3fe94fbbc1f72f613ec3e8f5084a8b26385dfa5ea46d96f3070254052a8;
        syncCommitteeRootDecommitments[15] = 0x6260533239f378c37f556b6873f1aef3adcb68b9dc21cfbd1a89c299ab6df33e;
        syncCommitteeRootDecommitments[16] = 0x634e2f5b591107dbd8037deb6e0207b591ccdb8be289d9a637b1bf00030442f6;
        syncCommitteeRootDecommitments[17] = 0xa82f2b4705953fd366aa10727f55c1892e57b3da2d9849ab3e08403b6dcef263;
        syncCommitteeRootDecommitments[18] = 0x11067b0b049b5654ab3fb510dca0f310f484cdb61fc8fa8875266ace100c0b8a;
        syncCommitteeRootDecommitments[19] = 0x2f6cf7199700ac1a5e6c5b334278aef1f6c6ac465e5036823e83a984e0851e51;
        syncCommitteeRootDecommitments[20] = 0xf0bc1858b032e074464529b2279777ad74d88d5f17fc18eb24eee4eab4e6e813;
        syncCommitteeRootDecommitments[21] = 0xb2a8bb779dddbf43862a0fbcca1b95dac502ef7e61eb23ad0b325a102228836d;
        syncCommitteeRootDecommitments[22] = 0xbcdc57c846dfb93aa32b1d65594e50e5de86e10feaae8d06ce611cdbb0ccfdae;
        syncCommitteeRootDecommitments[23] = 0xe3879df79d978de9442ae9d8e702febe0d9394c1f4a2faa0c75230db5e1c03da;
        syncCommitteeRootDecommitments[24] = 0x1095528ba8f42e2e687b0263999977ff0e1bb2cf9f4979a0a840c1655f9de296;
        syncCommitteeRootDecommitments[25] = 0xc1caa8eb7eed747aa28432742e00138b492451ed0bfcbb531a8c7191c40228a9;
        bytes32 root = Merkle.restoreMerkleMultiRoot(indices, leaves, syncCommitteeRootDecommitments);
        assertEq(root, 0xeb405d3c0880c162314e094b84f5fd210eae6b5755f26347a0e35b29481e6e6e);
    }
}
