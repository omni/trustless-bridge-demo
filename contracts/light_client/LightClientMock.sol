pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

import "./interfaces/IBeaconLightClient.sol";
import "./utils/CryptoUtils.sol";
import "./LightClient.sol";

abstract contract LightClientMock is LightClient {
    function setHead(uint256 _slot, StorageBeaconBlockHeader memory _header) internal {
        _setHead(_slot, _header);
    }
}
