pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "../contracts/light_client/LightClientChain.sol";
import "../contracts/light_client/mocks/BeaconLightClientMock.sol";

contract LightClientChainTest is Test {
    bytes32 emptyRoot = bytes32(0);

    BeaconLightClientMock homeLightClient;
    BeaconLightClientMock foreignLightClient;
    LightClientChain homeChain;
    LightClientChain foreignChain;

    function zeroHash(uint n) internal pure returns (bytes32) {
        bytes32 x = bytes32(0);
        for (uint256 i = 0; i < n; i++) {
            x = sha256(abi.encode(uint256(x), uint256(x)));
        }
        return x;
    }

    function setUp() public {
        homeLightClient = new BeaconLightClientMock();
        foreignLightClient = new BeaconLightClientMock();
        homeChain = new LightClientChain(IBeaconLightClient(address(homeLightClient)));
        foreignChain = new LightClientChain(IBeaconLightClient(address(foreignLightClient)));
    }

    function testVerifyExecutionPayloadSameSlot() public {
        ILightClientChain.ExecutionPayloadHeader memory payload = ILightClientChain.ExecutionPayloadHeader(
            bytes32(0x9a6903580f32976ea5aeae5d953fbe551566a9ea5482777ea1109278848e2a44),
            address(0x087465D0ddc872fc27901E45c861E6956622eb66),
            bytes32(0xfc4c274f169299e84439edda9a5b5a50cea6083f446cbcacb86b935ebc1abe52),
            bytes32(0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421),
            zeroHash(3),
            bytes32(0xe533b0c0d9515b062758d624aa850e641a4d5bcf954636a396e948478a4aae9c),
            211,
            14129666,
            0,
            1656607052,
            zeroHash(1),
            7,
            bytes32(0x0584634c87316fe8c91024188f458064ae3f7c72a1a45463dec288cebee03eb0),
            bytes32(0x7ffe241ea60187fdb0187bfa22de35d1f9bed7ab061d9401fd47e34a54fbede1)
        );
        homeLightClient.setHead(130, bytes32(0), 0x4e4b81179cd13b9fa08b0ec8494fc146bb11565aafcfa2bd1376780440cae7e1);
        bytes32[] memory payloadProof = new bytes32[](5);
        assertEq(homeChain.hashExecutionPayload(payload), 0xed034efe2091409b869b0fc1a239aeeb919d4bee32858700b4d775b5a1217296);
        payloadProof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        payloadProof[1] = 0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b;
        payloadProof[2] = 0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71;
        payloadProof[3] = 0x7e2d8c2faadd1d088bd9993ac2cd95fd596fe2de70bba7a9ea7c5938dfb15a49;
        payloadProof[4] = 0x83d57bfcc7729a21e286b53560b412d664055ec262a9a42fa7df629d877ba9a5;
        homeChain.verifyExecutionPayload(130, 130, payload, payloadProof);
    }

    function testVerifyExecutionPayloadTransitive() public {
        ILightClientChain.ExecutionPayloadHeader memory payload = ILightClientChain.ExecutionPayloadHeader(
            bytes32(0x9a6903580f32976ea5aeae5d953fbe551566a9ea5482777ea1109278848e2a44),
            address(0x087465D0ddc872fc27901E45c861E6956622eb66),
            bytes32(0xfc4c274f169299e84439edda9a5b5a50cea6083f446cbcacb86b935ebc1abe52),
            bytes32(0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421),
            zeroHash(3),
            bytes32(0xe533b0c0d9515b062758d624aa850e641a4d5bcf954636a396e948478a4aae9c),
            211,
            14129666,
            0,
            1656607052,
            zeroHash(1),
            7,
            bytes32(0x0584634c87316fe8c91024188f458064ae3f7c72a1a45463dec288cebee03eb0),
            bytes32(0x7ffe241ea60187fdb0187bfa22de35d1f9bed7ab061d9401fd47e34a54fbede1)
        );
        homeLightClient.setHead(150, bytes32(0), 0x13a3efe87011388ea7affab63620ad6272c324b90a141040c60932f1b59a61f7);
        bytes32[] memory payloadProof = new bytes32[](23);
        payloadProof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        payloadProof[1] = 0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b;
        payloadProof[2] = 0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71;
        payloadProof[3] = 0x7e2d8c2faadd1d088bd9993ac2cd95fd596fe2de70bba7a9ea7c5938dfb15a49;
        payloadProof[4] = 0x83d57bfcc7729a21e286b53560b412d664055ec262a9a42fa7df629d877ba9a5;
        payloadProof[5] = 0x77282e2fbb6b907f6c6be138955b8464cceaec974f860a2796050c8564dfac48;
        payloadProof[6] = 0x2af31edea42813021ce79ddaaa122c033dc28342953000d10629ae30f0c64ef1;
        payloadProof[7] = 0x7938fe8d4a7bb119b0b4c5dcbe6a1382de25d5dd29bc1a097ae0a1c6ed7e5e81;
        payloadProof[8] = 0xd44ed4b1c9e1e0304a060bd7a2ab7751768b355534ddf53a666a2a09e6747869;
        payloadProof[9] = 0x93763ac584eb70b67f382df2a756927e92692ad921cadfcb6e420d53a76033d9;
        payloadProof[10] = 0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30;
        payloadProof[11] = 0xd88ddfeed400a8755596b21942c1497e114c302e6118290f91e6772976041fa1;
        payloadProof[12] = 0xb74f882211bdbae4113569acb4fe0343127ea1200c7ae1f39e80347cfe9a1c6a;
        payloadProof[13] = 0x26846476fd5fc54a5d43385167c95144f2643f533cc85bb9d16b782f8d7db193;
        payloadProof[14] = 0x506d86582d252405b840018792cad2bf1259f1ef5aa5f887e13cb2f0094f51e1;
        payloadProof[15] = 0xffff0ad7e659772f9534c195c815efc4014ef1e1daed4404c06385d11192e92b;
        payloadProof[16] = 0x6cf04127db05441cd833107a52be852868890e4317e6a02ab47683aa75964220;
        payloadProof[17] = 0xb7d05f875f140027ef5118a2247bbb84ce8f2f0f1123623085daf7960c329f5f;
        payloadProof[18] = 0xa75b0948052d091c3cb41f390e76fc7cb987b787bf4063c563e09266a357dea1;
        payloadProof[19] = 0x2120203dbe7b39e92f65f84ddfb33d3df03b249a07064f915dd440986d5e248c;
        payloadProof[20] = 0xe4e5429fc4ba0d808e9ed784e7eace866e30d38fb5ba9b9ade8213f180e6a978;
        payloadProof[21] = 0x0578917b0900347981155937f8547b9d9c34f4fd3148f7631e50b0f93267df4e;
        payloadProof[22] = 0x323cc95c7246cfb83985f8f27ed09c26cdec9356149ce6ce0051e169856e1fc0;
        homeChain.verifyExecutionPayload(150, 130, payload, payloadProof);
    }

    function testVerifyExecutionPayloadTransitiveAncient() public {
        ILightClientChain.ExecutionPayloadHeader memory payload = ILightClientChain.ExecutionPayloadHeader(
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            address(0x0000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            zeroHash(3),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            0,
            0,
            0,
            0,
            zeroHash(1),
            0,
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000)
        );
        homeLightClient.setHead(8256, bytes32(0), 0x1db8b0992b1daec4054983e6d3f983f08df3415e99bb5f4f2ccffad49cfa4a18);
        bytes32[] memory payloadProof = new bytes32[](49);
        payloadProof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        payloadProof[1] = 0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b;
        payloadProof[2] = 0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71;
        payloadProof[3] = 0x6aa1ca3f0ba9d08f7877ed7c9af0372b8db6a8e9cd5db8dd7d7f37e9924f9bf1;
        payloadProof[4] = 0x4f1ab95a3fa19247bc626bec04aaa3c7134428af91b66dc7062a55da0023e004;
        payloadProof[5] = 0xc8f871c3e5ed19d14b3b46746b1ced7a60e3196013215aeae8fd4a323a7e29fc;
        payloadProof[6] = 0x54a747f7134ae43fa9a7a85867bbe395c3b8bda1f2bd81a87943b6b87fb06042;
        payloadProof[7] = 0xa995c132bbec2dabca1fa3926436850a51320b6d6f27ad984cc5bfec0aba7626;
        payloadProof[8] = 0xc24a22399299914fdc12824a055f5a15536b8eadfade08673fa90473367269c1;
        payloadProof[9] = 0xfd58b061e981e4f246a88a7ac68285cfe63d535b607f8a4691c645eda2681d67;
        payloadProof[10] = 0x76a7f367c71b7f1f419664f84b121f486718a1b59034c677655a5b63f39e22d0;
        payloadProof[11] = 0x9d39908f886dd9ac360628bbefc001a012f0336a55ac51c23313b80189ef1b4b;
        payloadProof[12] = 0x0e7dcf9307d0a9d3e90f139d3b01419f6d9110974c71de99706a688712c28347;
        payloadProof[13] = 0xf9d68a03835474f54f458591cdde2154c2202907a73657afc3dcf27ab3904781;
        payloadProof[14] = 0x363835bb52d4b517f9a745c2bf957211348cc259665ccd2e85555cd5a5f0a82f;
        payloadProof[15] = 0xb9ad0f9f3bf66d928fe7a146f3af9cd47429029114b636287c7ce50abf83bd61;
        payloadProof[16] = 0x60d4d5fa50646effc8a42b6b4a5e7f9855fc4524c3e639fcf8aaae3709c37b1c;
        payloadProof[17] = 0x124e0416be1990e31f1612a0fb9bb72570d67b1f78455d009ac152f65b4f8b48;
        payloadProof[18] = 0x4fccea4e24fcfe4dca69f7aa51bc8b74e1b6dc5c2cbf08b6781d0af86a715d02;
        payloadProof[19] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        payloadProof[20] = 0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b;
        payloadProof[21] = 0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71;
        payloadProof[22] = 0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c;
        payloadProof[23] = 0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c;
        payloadProof[24] = 0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30;
        payloadProof[25] = 0xd88ddfeed400a8755596b21942c1497e114c302e6118290f91e6772976041fa1;
        payloadProof[26] = 0x87eb0ddba57e35f6d286673802a4af5975e22506c7cf4c64bb6be5ee11527f2c;
        payloadProof[27] = 0x26846476fd5fc54a5d43385167c95144f2643f533cc85bb9d16b782f8d7db193;
        payloadProof[28] = 0x506d86582d252405b840018792cad2bf1259f1ef5aa5f887e13cb2f0094f51e1;
        payloadProof[29] = 0xffff0ad7e659772f9534c195c815efc4014ef1e1daed4404c06385d11192e92b;
        payloadProof[30] = 0x6cf04127db05441cd833107a52be852868890e4317e6a02ab47683aa75964220;
        payloadProof[31] = 0xb7d05f875f140027ef5118a2247bbb84ce8f2f0f1123623085daf7960c329f5f;
        payloadProof[32] = 0xdf6af5f5bbdb6be9ef8aa618e4bf8073960867171e29676f8b284dea6a08a85e;
        payloadProof[33] = 0xb58d900f5e182e3c50ef74969ea16c7726c549757cc23523c369587da7293784;
        payloadProof[34] = 0xd49a7502ffcfb0340b1d7885688500ca308161a7f96b62df9d083b71fcc8f2bb;
        payloadProof[35] = 0x8fe6b1689256c0d385f42f5bbe2027a22c1996e110ba97c171d3e5948de92beb;
        payloadProof[36] = 0x8d0d63c39ebade8509e0ae3c9c3876fb5fa112be18f905ecacfecb92057603ab;
        payloadProof[37] = 0x95eec8b2e541cad4e91de38385f2e046619f54496c2382cb6cacd5b98c26f5a4;
        payloadProof[38] = 0xf893e908917775b62bff23294dbbe3a1cd8e6cc1c35b4801887b646a6f81f17f;
        payloadProof[39] = 0xcddba7b592e3133393c16194fac7431abf2f5485ed711db282183c819e08ebaa;
        payloadProof[40] = 0x8a8d7fe3af8caa085a7639a832001457dfb9128a8061142ad0335629ff23ff9c;
        payloadProof[41] = 0xfeb3c337d7a51a6fbf00b9e34c52e1c9195c969bd4e7a0bfd51d5c5bed9c1167;
        payloadProof[42] = 0xe71f0aa83cc32edfbefa9f4d3e0174ca85182eec9f3a09f6a6c0df6377a510d7;
        payloadProof[43] = 0x0100000000000000000000000000000000000000000000000000000000000000;
        payloadProof[44] = 0xea0b6a407c42f5781b849fe016c86258d2ebdde5943c52720d7746c501625483;
        payloadProof[45] = 0x14120ffb33a90c71ad2ffd3943e1e715e2941ba2d4a86bf8eaceb213db970794;
        payloadProof[46] = 0x31daa39ccbf3e871479656d52e101817677ee8804f0335b7d57e56a264cdf48e;
        payloadProof[47] = 0x758f7742f0701a515461d2cd2fc60d1f3d6f5f7fe9f1179e1a03c77e1bb98961;
        payloadProof[48] = 0xbe69831be4716e3013d672854038075943b3f3a1259bc1b1d364e5d918779ec6;
        homeChain.verifyExecutionPayload(8256, 47, payload, payloadProof);
    }
}
