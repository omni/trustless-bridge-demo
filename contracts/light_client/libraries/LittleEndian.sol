pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

library LittleEndian {
    function encode(uint256 x) internal pure returns (bytes32) {
        bytes32 res;
        for (uint256 i = 0; i < 32; i++) {
            res = (res << 8) | bytes32(x & 0xff);
            x >>= 8;
        }
        return res;
    }
}
