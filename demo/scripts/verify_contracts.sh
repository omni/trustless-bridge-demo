#!/bin/bash

set -e

source ./vars/contracts.env

function verify_contract() {
  name=$(basename $2)
  cmd="INSERT INTO smart_contracts (
      name, compiler_version, optimization,
      contract_source_code, abi, address_hash,
      contract_code_md5, inserted_at, updated_at
    ) VALUES (
      '${name%.*}', 'foundry', true,
      \$\$$(cat $3)\$\$, '$(cat $2 | jq -r .abi)'::jsonb, '\\${4:1}',
      '', now(), now()
    ) ON CONFLICT DO NOTHING"
  docker exec $1-postgres psql -U postgres -d blockscout -c "$cmd"
}

verify_contract home ../out/BeaconLightClient.sol/BeaconLightClient.json ../contracts/light_client/BeaconLightClient.sol $HOME_LIGHT_CLIENT
verify_contract home ../out/EIP1967Proxy.sol/EIP1967Proxy.json ../contracts/amb/proxy/EIP1967Proxy.sol $HOME_AMB
verify_contract home ../out/TrustlessAMB.sol/TrustlessAMB.json ../contracts/amb/TrustlessAMB.sol $HOME_AMB_IMPL
verify_contract home ../out/EternalStorageProxy.sol/EternalStorageProxy.json ../contracts/omnibridge/upgradeability/EternalStorageProxy.sol $HOME_OB
verify_contract home ../out/HomeOmnibridge.sol/HomeOmnibridge.json ../contracts/omnibridge/upgradeable_contracts/HomeOmnibridge.sol $HOME_OB_IMPL
verify_contract home ../out/WETH.sol/WETH.json ../contracts/omnibridge/mocks/WETH.sol $HOME_WETH
verify_contract home ../out/WETHOmnibridgeRouter.sol/WETHOmnibridgeRouter.json ../contracts/omnibridge/helpers/WETHOmnibridgeRouter.sol $HOME_ROUTER

verify_contract foreign ../out/BeaconLightClient.sol/BeaconLightClient.json ../contracts/light_client/BeaconLightClient.sol $FOREIGN_LIGHT_CLIENT
verify_contract foreign ../out/EIP1967Proxy.sol/EIP1967Proxy.json ../contracts/amb/proxy/EIP1967Proxy.sol $FOREIGN_AMB
verify_contract foreign ../out/TrustlessAMB.sol/TrustlessAMB.json ../contracts/amb/TrustlessAMB.sol $FOREIGN_AMB_IMPL
verify_contract foreign ../out/EternalStorageProxy.sol/EternalStorageProxy.json ../contracts/omnibridge/upgradeability/EternalStorageProxy.sol $FOREIGN_OB
verify_contract foreign ../out/ForeignOmnibridge.sol/ForeignOmnibridge.json ../contracts/omnibridge/upgradeable_contracts/ForeignOmnibridge.sol $FOREIGN_OB_IMPL
verify_contract foreign ../out/WETH.sol/WETH.json ../contracts/omnibridge/mocks/WETH.sol $FOREIGN_WETH
verify_contract foreign ../out/WETHOmnibridgeRouter.sol/WETHOmnibridgeRouter.json ../contracts/omnibridge/helpers/WETHOmnibridgeRouter.sol $FOREIGN_ROUTER
