pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "../contracts/amb/libraries/MPT.sol";

contract MPTTest is Test {
    function testSimplePath() public {
        bytes32 key = 0x3f6f2497fb590e494002b67c712e1fba86767d2906fb8e1ddae48d2b7d91908b;
        bytes[] memory proof = new bytes[](4);
        proof[0] = hex"f901d1a01823e96f74a3c82318631318cd929217a62f4093f245594ac91c52bd9163de35a05a180f5ba06bfecafea1b26316654845e16788795d43ba3bc7dc5a44d007b87a80a0f619c44e7897cedf6d4db8fd11bfef25595b04bdb6dc57dd10a24794a9e99821a03d993a2d29b0863ef075e0fd33380c5e762440c6f255a1fa8439d731c8500244a0c9cd6532fc826b640d79cf1ae443c6969b93af3c97730988b7eb329d9789fe75a091dc8ecb25dbe2f01658da8d66a9441e144cff713112dbbc66e3e82fb0d32adfa038503551b5a0079aad0fb9244f733d88f21416aa7d0cd5a19a5199e75b480403a09c985fa4506cfca47d82caf0bb814824da33458f9691000fb9c52bc8e00b6f7380a0028495b90824a9dcbd176ce3d638cab20fe38a386573c56540473c15f7ea3980a0e68fdeaec5c496cddef6a4222be9d35d4d97dac8ae9f27a0df020dee26f68467a0198fdfbe2bde38fdf169a7ba7be153e149daaf2f156ce03b9f78615832ac7178a0234c688922e00ac36f131d70ddb00ad140853d627d056acbf8ed275f2e0b7af3a0adba07f249c387c0e176b056f0223d1fdd81955907ee57e72315aacb5781876aa076d729da54a3f91564e305e092aa9455fd32a2ccc1aacc916c808a4f98b47ae980";
        proof[1] = hex"e21fa0b2aae8ff9916f94112b0a48565d4afde963cbdc5e1b624b87dbd11ad9a7b639b";
        proof[2] = hex"f851808080808080a0f80a6b11fa804edbe70615eaf78f8082390d5c105ef78f5603ed61ed3c3f485f8080a0572eb4281cf1d0c2f7103d453f2e364b6c5e9fbf240839bf83525f921972fee980808080808080";
        proof[3] = hex"f8429f3f2497fb590e494002b67c712e1fba86767d2906fb8e1ddae48d2b7d91908ba1a067b2790746b16ac2c2c5c5b2f12128055593c98da12a8d4b5c45bf6f94ebf9bf";
        bytes memory value = MPT.readProof(key, proof);
        assertEq(value, hex"a067b2790746b16ac2c2c5c5b2f12128055593c98da12a8d4b5c45bf6f94ebf9bf");
    }
}