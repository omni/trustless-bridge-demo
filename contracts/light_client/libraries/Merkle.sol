pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

library Merkle {
    function restoreMerkleRoot(
        bytes32 leaf,
        uint256 genIndex,
        bytes32[] memory proof
    ) internal view returns (bytes32) {
        require(genIndex >> proof.length == 1, "invalid proof length");
        for (uint256 i = 0; i < proof.length; i++) {
            if (genIndex & (1 << i) == 0) {
                leaf = hashPair(leaf, proof[i]);
            } else {
                leaf = hashPair(proof[i], leaf);
            }
        }
        return leaf;
    }

    function restoreMerkleMultiRoot(
        uint256[] memory indices,
        bytes32[] memory hashes,
        bytes32[] memory decommitments
    ) internal view returns (bytes32) {
        uint256 n = indices.length;
        require(n == hashes.length, "Arrays lengths mismatch");
        if (n == 0) {
            return decommitments[0];
        }

        uint256 head = 0;
        uint256 tail = 0;
        uint256 di = 0;
        uint256 index;
        bytes32 hash;

        while (true) {
            assembly {
                index := mload(add(indices, mul(add(head, 1), 0x20)))
                hash := mload(add(hashes, mul(add(head, 1), 0x20)))
                head := mod(add(head, 1), n)
            }

            if (index == 1) {
                return hash;
            } else if (index & 1 == 0) {
                // Even node, take sibling from decommitments
                hash = hashPair(hash, decommitments[di++]);
            } else if (indices[head] == index - 1 && head != tail) {
                // Odd node with sibling in the queue
                hash = hashPair(hashes[head], hash);
                head = (head + 1) % n;
            } else {
                // Odd node with sibling from decommitments
                hash = hashPair(decommitments[di++], hash);
            }

            assembly {
                mstore(add(indices, mul(add(tail, 1), 0x20)), div(index, 2))
                mstore(add(hashes, mul(add(tail, 1), 0x20)), hash)
                tail := mod(add(tail, 1), n)
            }
        }
    }

    function hashPair(bytes32 a, bytes32 b) internal view returns (bytes32 c) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            let status := staticcall(gas(), 0x02, 0x00, 0x40, 0x00, 0x20)
            if iszero(status) {
                revert(0, 0)
            }
            c := mload(0x00)
        }
    }
}
