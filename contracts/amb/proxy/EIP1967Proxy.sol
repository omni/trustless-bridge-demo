pragma solidity 0.8.14;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "./EIP1967Admin.sol";

/**
 * @title EIP1967Proxy
 * @dev Upgradeable proxy pattern implementation according to minimalistic EIP1967.
 */
contract EIP1967Proxy is EIP1967Admin, Proxy {
    // EIP 1967
    // bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)
    uint256 internal constant EIP1967_IMPLEMENTATION = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);

    constructor(address _newAdmin, address _newImplementation, bytes memory _data) payable {
        _setAdmin(_newAdmin);
        _upgradeToAndCall(_newImplementation, _data);
    }

    function setAdmin(address _admin) external onlyAdmin {
        _setAdmin(_admin);
    }

    function upgradeToAndCall(address _newImplementation, bytes memory _data) external onlyAdmin payable {
        _upgradeToAndCall(_newImplementation, _data);
    }

    function _upgradeToAndCall(address _newImplementation, bytes memory _data) internal {
        _setImplementation(_newImplementation);
        if (_data.length > 0) {
            (bool status,) = _newImplementation.delegatecall(_data);
            require(status, "EIP1967Proxy: call failed");
        }
    }

    /**
     * @dev Internal function for transfer current admin rights to a different account.
     * @param _newAdmin address of the new administrator.
     */
    function _setAdmin(address _newAdmin) internal {
        address previousAdmin = _admin();
        require(_newAdmin != address(0));
        assembly {
            sstore(EIP1967_ADMIN, _newAdmin)
        }
        emit AdminChanged(previousAdmin, _newAdmin);
    }

    /**
     * @dev Internal function for setting a new implementation address.
     * @param _newImplementation address of the new implementation contract.
     */
    function _setImplementation(address _newImplementation) internal {
        require(_newImplementation != address(0));
        assembly {
            sstore(EIP1967_IMPLEMENTATION, _newImplementation)
        }
        emit Upgraded(_newImplementation);
    }

    function _implementation() internal view override returns (address res) {
        assembly {
            res := sload(EIP1967_IMPLEMENTATION)
        }
    }
}
