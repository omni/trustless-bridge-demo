pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

library Merkle {
    function restoreMerkleRoot(
        bytes32 leaf,
        uint256 genIndex,
        bytes32[] memory proof
    ) internal returns (bytes32) {
        require(genIndex >> proof.length == 1, "invalid proof length");
        for (uint256 i = 0; i < proof.length; i++) {
            if (genIndex & (1 << i) == 0) {
                leaf = sha256(abi.encodePacked(leaf, proof[i]));
            } else {
                leaf = sha256(abi.encodePacked(proof[i], leaf));
            }
        }
        return leaf;
    }
}
