pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "../contracts/amb/TrustlessAMB.sol";
import "../contracts/light_client/mocks/LightClientChainMock.sol";

contract TrustlessAMBTest is Test {
    bytes32 emptyRoot = bytes32(0);

    LightClientChainMock homeChain;
    LightClientChainMock foreignChain;
    TrustlessAMB home;
    TrustlessAMB foreign;

    function setUp() public {
        homeChain = new LightClientChainMock();
        homeChain.setHead(
            1000,
            0x761f35ed043ea6aaf33a1f29a1774efc4616db156c06122771a971f9a94e0100,
            0x658b7a574440f539fe81cfa894dc23776a77c42fe5ab96ebfe78c194d6f8c2f3
        );
    }

    function testStorageProof() public {
        foreign = new TrustlessAMB();
        foreign.initialize(address(homeChain), 2000000, address(0xb44ea27353D96890CB6adD8D5F7De6837bD3322a));
        bytes memory message = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000077b45697f481308c8e4f3e18d49e27a6db3d1aa000000000000000000000000077b45697f481308c8e4f3e18d49e27a6db3d1aa000000000000000000000000000000000000000000000000000000000001e848000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001442ae87cdd0000000000000000000000002030fe144bfb3b4b4a06a1aedceddde43b48cd6b00000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000001200000000000000000000000055578a741a4c74ee8a5b7197daea322fcc8937140000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000d57726170706564204574686572000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004574554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes[] memory proof1 = new bytes[](3);
        bytes[] memory proof2 = new bytes[](2);
        proof1[0] = hex"f9019180a04e160a0159b3fc78878473cad0313340a4b11e528d6ce7f18135b4883df0e804a05b314f147b1fb972527510ed991db9e2a8cd3e78b087519b4e908692d56d0d1e80a01a697e814758281972fcd13bc9707dbcd2f195986b05463d7b78426508445a04a044f9cefd620bc1fbfdf30074f3d24abbeadd7a2abba55b7380414508df4511a1a0c2c799b60a0cd6acd42c1015512872e86c186bcf196e85061e76842f3b7cf86080a02e0d86c3befd177f574a20ac63804532889077e955320c9361cd10b7cc6f5809a028e8de74350bbb410817cf3d59412347cd1e8a95d3ff86d717241c52ceba3112a06301b39b2ea8a44df8b0356120db64b788e71f52e1d7a6309d0d2e5b86fee7cb80a02eb6c1853400d160b7cb6b35765adc839297368b0d8e729ce46209ad99e63b57a01b7779e149cadf24d4ffb77ca7e11314b8db7097e4d70b2a173493153ca2e5a0a0fb93126e1d0713a4e8192db47e6b064fe8a8d5460853af60760311908d762b44a0931925a51a187e2d5d5ff5036b4418660988b4c5d9f878f8dec51ac19d667ced80";
        proof1[1] = hex"f85180808080a09b7cbe4571577a607f9db98bda7f15edc2d514c3f88b4d03ee5375f5ceba79cc80a0cacac8af74fb8b82e5f59018d98c7126226306b54f0412da3ff5818509fe1b9a80808080808080808080";
        proof1[2] = hex"f869a020debdd37df58f72ba0cb2bf3b3cb803dcb0ab59578ff64672ee960d44b765f4b846f8440180a0f31ec3450ef68ea5b32c224a35738d8a61dd0afd22fcb98c718341d87a041e8da083a9d161e1390570f3f5c88f938ea9e1a17f13f26d636e9b9441cfe51d15173f";

        proof2[0] = hex"f8f1a03e83d6c02334041f974bf336ed2ef8956d3ff12001afd0732fa1800f779316d5808080a0c36876eba968a07d528dcb3edfcf211066d1bc136f0625d06a78b44b8dec6281a0c9cd6532fc826b640d79cf1ae443c6969b93af3c97730988b7eb329d9789fe7580a045ba96f416399dea66992fae365e3ce155e72c87c1f6a3776ba70835b73d67bba0071b011fdbd4ad7d1e6f9762be4d1a88dffde614a6bd399bf3b5bad8f41249b5808080a0aebd8705fa09b784c96272b35231069461fc62579a460279cc0f0258a3fa69248080a03faed6cc9a008d4bb8c0d587b3644503fb735ab6ac02d2dcdab832712012f1ed80";
        proof2[1] = hex"f843a030df3dcda05b4fbd9c655cde3d5ceb211e019e72ec816e127a59e7195f2cd7f5a1a0f3fab4a7cde39c423e7ce15771059a82627e321550cb830ebbb1bac84142ad29";
        foreign.executeMessage(1000, message, proof1, proof2);
    }

    function testLogProof() public {
        foreign = new TrustlessAMB();
        foreign.initialize(address(homeChain), 2000000, address(0x2030fe144BfB3B4B4A06a1aedCeddde43B48Cd6b));
        bytes memory message = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000079d450276243a2fc58efcbf4a99e6fb83352f41000000000000000000000000079d450276243a2fc58efcbf4a99e6fb83352f41000000000000000000000000000000000000000000000000000000000001e848000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001442ae87cdd00000000000000000000000077b45697f481308c8e4f3e18d49e27a6db3d1aa000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000001200000000000000000000000055578a741a4c74ee8a5b7197daea322fcc8937140000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000d57726170706564204574686572000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004574554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes[] memory proof = new bytes[](1);
        proof[0] = hex"f906c4822080b906be02f906ba0183064ab5b9010000000000000000080080000000001000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000020000000000000000088000000000000010000000010000000008000020200040002024000000080080000000800000000000000000000100010000100000000000000040000100000000200000000000001000000001000080000000000000000000000480000000000000000000000000000000200000000000000000000000402000000000000000000000100000000000000000000000000002020000000000008000000000000000000000000000000200000400000040000002000f905aff87a9477b45697f481308c8e4f3e18d49e27a6db3d1aa0f842a0e1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109ca0000000000000000000000000e850a7a9e2336f8364015da3cb9d7b2bb020f91aa00000000000000000000000000000000000000000000000000de0b6b3a7640000f89b9477b45697f481308c8e4f3e18d49e27a6db3d1aa0f863a0ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3efa0000000000000000000000000e850a7a9e2336f8364015da3cb9d7b2bb020f91aa000000000000000000000000079d450276243a2fc58efcbf4a99e6fb83352f410a00000000000000000000000000000000000000000000000000de0b6b3a7640000f87a9479d450276243a2fc58efcbf4a99e6fb83352f410f842a0ca0b3dabefdbd8c72c0a9cf4a6e9d107da897abf036ef3f3f3b010cdd2594159a000000000000000000000000077b45697f481308c8e4f3e18d49e27a6db3d1aa0a00000000000000000000000000000000000000000000000056bc75e2d63100000f87a9479d450276243a2fc58efcbf4a99e6fb83352f410f842a04c177b42dbe934b3abbc0208c11a42e46589983431616f1710ab19969c5ed62ea000000000000000000000000077b45697f481308c8e4f3e18d49e27a6db3d1aa0a00000000000000000000000000000000000000000000000056bc75e2d63100000f902dd942030fe144bfb3b4b4a06a1aedceddde43b48cd6bf863a0d272c9b6e024bd86cfdcf4dac1c1db8e1c4bcdebd4a65967d5d0218ab0d55a1ea03d1fb9d5b94dc88ff427f281e0e5f55422b28c9c30dead3c69036feb2803c322a00000000000000000000000000000000000000000000000000000000000000000b9026000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000079d450276243a2fc58efcbf4a99e6fb83352f41000000000000000000000000079d450276243a2fc58efcbf4a99e6fb83352f41000000000000000000000000000000000000000000000000000000000001e848000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001442ae87cdd00000000000000000000000077b45697f481308c8e4f3e18d49e27a6db3d1aa000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000001200000000000000000000000055578a741a4c74ee8a5b7197daea322fcc8937140000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000d57726170706564204574686572000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004574554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f8bc9479d450276243a2fc58efcbf4a99e6fb83352f410f884a059a9a8027b9c87b961e254899821c9a276b5efc35d1f7409ea4f291470f1629aa000000000000000000000000077b45697f481308c8e4f3e18d49e27a6db3d1aa0a0000000000000000000000000e850a7a9e2336f8364015da3cb9d7b2bb020f91aa03d1fb9d5b94dc88ff427f281e0e5f55422b28c9c30dead3c69036feb2803c322a00000000000000000000000000000000000000000000000000de0b6b3a7640000";
        foreign.executeMessageFromLog(1000, 0, 4, message, proof);
    }
}