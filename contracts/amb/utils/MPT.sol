pragma solidity 0.8.14;

import "./RLPReader.sol";

contract MPT {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.Iterator;
    using RLPReader for bytes;

    function _nibble(bytes32 key, uint256 index) private pure returns (uint256 nibble) {
        assembly {
            nibble := shr(mul(4, sub(63, index)), key)
        }
        return nibble % 16;
    }

    function _decodePathLength(bytes memory path) private pure returns (uint256, bool) {
        uint256 nibble = uint256(uint8(path[0]));
        return ((path.length-1)*2 + nibble%2, nibble > 1);
    }

    function _verifyMPTProof(
        bytes32 root,
        bytes32 key,
        bytes[] memory proof
    ) internal pure returns (bytes memory) {
        uint256 currentPathLength = 0;
        bytes32 currentHash = root;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes memory node = proof[i];
            bytes32 hash = keccak256(node);
            require(root == hash, string(abi.encodePacked("MPT: node hash does not match", uint8(i + 0x30))));

            RLPReader.RLPItem[] memory ls = node.toRlpItem().toList();
            if (ls.length == 17) {
                uint256 nibble = _nibble(key, currentPathLength++);
                root = bytes32(ls[nibble].toUint());
            } else {
                require(ls.length == 2, "MPT: invalid RLP list length");
                (uint256 extensionPathLength, bool isLeaf) = _decodePathLength(ls[0].toBytes());
                node = ls[1].toBytes();
                currentPathLength += extensionPathLength;
                if (isLeaf) {
                    require(currentPathLength == 64, "MPT: invalid leaf path length");
                    return node;
                } else {
                    root = keccak256(node);
                }
            }
        }
        revert("MPT: invalid proof");
    }
}
