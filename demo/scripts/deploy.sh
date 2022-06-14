#!/bin/bash

set -e

source ./vars/vars.env

CONTRACTS=../contracts
LIGHT_CLIENT=$CONTRACTS/light_client/LightClient.sol:LightClient
TRUSTLESS_AMB=$CONTRACTS/amb/TrustlessAMB.sol:TrustlessAMB
EIP1967_PROXY=$CONTRACTS/amb/proxy/EIP1967Proxy.sol:EIP1967Proxy
WETH=$CONTRACTS/omnibridge/mocks/WETH.sol:WETH
PROXY=$CONTRACTS/omnibridge/upgradeability/EternalStorageProxy.sol:EternalStorageProxy
TOKEN_IMAGE=$CONTRACTS/omnibridge/tokens/PermittableToken_flat.sol:PermittableToken
TOKEN_FACTORY=$CONTRACTS/omnibridge/upgradeable_contracts/modules/factory/TokenFactory.sol:TokenFactory
FEE_MANAGER=$CONTRACTS/omnibridge/upgradeable_contracts/modules/fee_manager/OmnibridgeFeeManager.sol:OmnibridgeFeeManager
GAS_MANAGER=$CONTRACTS/omnibridge/upgradeable_contracts/modules/gas_limit/SelectorTokenGasLimitManager.sol:SelectorTokenGasLimitManager
HOME_OB_IMPL=$CONTRACTS/omnibridge/upgradeable_contracts/HomeOmnibridge.sol:HomeOmnibridge
FOREIGN_OB_IMPL=$CONTRACTS/omnibridge/upgradeable_contracts/ForeignOmnibridge.sol:ForeignOmnibridge
WETH_ROUTER=$CONTRACTS/omnibridge/helpers/WETHOmnibridgeRouter.sol:WETHOmnibridgeRouter

HOME_GENESIS_TIME=$(curl -s $HOME_BN_URL/eth/v1/beacon/genesis | jq -r .data.genesis_time)
HOME_GENESIS_VALIDATORS_ROOT=$(curl -s $HOME_BN_URL/eth/v1/beacon/genesis | jq -r .data.genesis_validators_root)
HOME_GENESIS_HEADER_DATA=$(curl -s $HOME_BN_URL/eth/v1/beacon/headers/$HOME_START_SLOT | jq .data.header.message | jq -r '[.slot,.proposer_index,.parent_root,.state_root,.body_root] | join(",")')
FOREIGN_GENESIS_TIME=$(curl -s $FOREIGN_BN_URL/eth/v1/beacon/genesis | jq -r .data.genesis_time)
FOREIGN_GENESIS_VALIDATORS_ROOT=$(curl -s $FOREIGN_BN_URL/eth/v1/beacon/genesis | jq -r .data.genesis_validators_root)
FOREIGN_GENESIS_HEADER_DATA=$(curl -s $FOREIGN_BN_URL/eth/v1/beacon/headers/$FOREIGN_START_SLOT | jq .data.header.message | jq -r '[.slot,.proposer_index,.parent_root,.state_root,.body_root] | join(",")')

function deploy() {
  RPC_URL=$1
  CONTRACT=$2
  shift
  shift
  if [ "$#" -gt 0 ]; then
    res=$(forge create --keystore $(pwd)/vars/keys/key_deployer.json --password '' --rpc-url "$RPC_URL" --constructor-args $@ --json "$CONTRACT")
  else
    res=$(forge create --keystore $(pwd)/vars/keys/key_deployer.json --password '' --rpc-url "$RPC_URL" --json "$CONTRACT")
  fi
  echo $res | jq -r .deployedTo
}

function send() {
  res=$(cast send --keystore $(pwd)/vars/keys/key_deployer.json --password '' --rpc-url $@)
  echo $res | grep transactionHash
}

echo "Deploying LightClient pair"

HOME_LIGHT_CLIENT=$(deploy $HOME_RPC_URL $LIGHT_CLIENT \
  $FOREIGN_GENESIS_VALIDATORS_ROOT $FOREIGN_GENESIS_TIME $LIGHT_CLIENT_UPDATE_TIMEOUT "($FOREIGN_GENESIS_HEADER_DATA,0,$(cast hz))")
echo "Deployed Home LightClient at $HOME_LIGHT_CLIENT"

FOREIGN_LIGHT_CLIENT=$(deploy $FOREIGN_RPC_URL $LIGHT_CLIENT \
  $HOME_GENESIS_VALIDATORS_ROOT $HOME_GENESIS_TIME $LIGHT_CLIENT_UPDATE_TIMEOUT "($HOME_GENESIS_HEADER_DATA,0,$(cast hz))")
echo "Deployed Foreign LightClient at $FOREIGN_LIGHT_CLIENT"


echo "Deploying TrustlessAMB implementations pair"

HOME_AMB_I=$(deploy $HOME_RPC_URL $TRUSTLESS_AMB)
FOREIGN_AMB_I=$(deploy $FOREIGN_RPC_URL $TRUSTLESS_AMB)

echo "Deploying TrustlessAMB pair"

HOME_AMB=$(cast compute-address --rpc-url $HOME_RPC_URL $ADMIN | cut -c18-)
echo "Computed Home TrustlessAMB address: $HOME_AMB"

FOREIGN_AMB=$(cast compute-address --rpc-url $FOREIGN_RPC_URL $ADMIN | cut -c18-)
echo "Computed Foreign TrustlessAMB address: $FOREIGN_AMB"

HOME_AMB_INIT_DATA=$(cast cd 'initialize(address,uint256,address)' $HOME_LIGHT_CLIENT 2000000 $FOREIGN_AMB)
FOREIGN_AMB_INIT_DATA=$(cast cd 'initialize(address,uint256,address)' $FOREIGN_LIGHT_CLIENT 2000000 $HOME_AMB)

HOME_AMB=$(deploy $HOME_RPC_URL $EIP1967_PROXY $ADMIN $HOME_AMB_I $HOME_AMB_INIT_DATA)
echo "Deployed Home TrustlessAMB at $HOME_AMB"

FOREIGN_AMB=$(deploy $FOREIGN_RPC_URL $EIP1967_PROXY $ADMIN $FOREIGN_AMB_I $FOREIGN_AMB_INIT_DATA)
echo "Deployed Foreign TrustlessAMB at $FOREIGN_AMB"


echo "Deploying WETH token pair"
HOME_WETH=$(deploy $HOME_RPC_URL $WETH)
echo "Deployed Home WETH at $HOME_WETH"
FOREIGN_WETH=$(deploy $FOREIGN_RPC_URL $WETH)
echo "Deployed Foreign WETH at $FOREIGN_WETH"


echo "Deploying EternalStorageProxy pair"
HOME_OB=$(deploy $HOME_RPC_URL $PROXY)
echo "Deployed Home EternalStorageProxy at $HOME_OB"
FOREIGN_OB=$(deploy $FOREIGN_RPC_URL $PROXY)
echo "Deployed Foreign EternalStorageProxy at $FOREIGN_OB"


echo "Deploying TokenImage pair"
HOME_TOKEN_IMAGE=$(deploy $HOME_RPC_URL $TOKEN_IMAGE "TokenImage" "IMG" 18 $HOME_CHAIN_ID)
echo "Deployed Home TokenImage at $HOME_TOKEN_IMAGE"
FOREIGN_TOKEN_IMAGE=$(deploy $FOREIGN_RPC_URL $TOKEN_IMAGE "TokenImage" "IMG" 18 $FOREIGN_CHAIN_ID)
echo "Deployed Foreign TokenImage at $FOREIGN_TOKEN_IMAGE"


echo "Deploying TokenFactory pair"
HOME_FACTORY=$(deploy $HOME_RPC_URL $TOKEN_FACTORY $ADMIN $HOME_TOKEN_IMAGE)
echo "Deployed Home TokenFactory at $HOME_FACTORY"
FOREIGN_FACTORY=$(deploy $FOREIGN_RPC_URL $TOKEN_FACTORY $ADMIN $FOREIGN_TOKEN_IMAGE)
echo "Deployed Foreign TokenFactory at $FOREIGN_FACTORY"


echo "Deploying HomeOmnibridge"
HOME_OB_I=$(deploy $HOME_RPC_URL $HOME_OB_IMPL '_from_Foreign')
echo "Deployed HomeOmnibridge at $HOME_OB_I"

echo "Deploying ForeignOmnibridge"
FOREIGN_OB_I=$(deploy $FOREIGN_RPC_URL $FOREIGN_OB_IMPL '_from_Home')
echo "Deployed ForeignOmnibridge at $FOREIGN_OB_I"


echo "Linking HomeOmnibridge"
send $HOME_RPC_URL $HOME_OB 'upgradeTo(uint256,address)' 1 $HOME_OB_I
echo "Linked HomeOmnibridge"

echo "Linking ForeignOmnibridge"
send $FOREIGN_RPC_URL $FOREIGN_OB 'upgradeTo(uint256,address)' 1 $FOREIGN_OB_I
echo "Linked ForeignOmnibridge"


echo "Deploying WETHOmnibridgeRouter pair"
HOME_ROUTER=$(deploy $HOME_RPC_URL $WETH_ROUTER $HOME_OB $HOME_WETH $ADMIN)
echo "Deployed Home WETHOmnibridgeRouter at $HOME_ROUTER"
FOREIGN_ROUTER=$(deploy $FOREIGN_RPC_URL $WETH_ROUTER $FOREIGN_OB $FOREIGN_WETH $ADMIN)
echo "Deployed Foreign WETHOmnibridgeRouter at $FOREIGN_ROUTER"


echo "Initializing HomeOmnibridge"
send $HOME_RPC_URL --gas 1000000 $HOME_OB 'initialize(address,address,uint256[3],uint256[2],address,address,address,address)' \
  $HOME_AMB \
  $FOREIGN_OB \
  "[$(cast tw 100),$(cast tw 10),$(cast tw 0.001)]" \
  "[$(cast tw 100),$(cast tw 10)]" \
  $(cast az) \
  $ADMIN \
  $HOME_FACTORY \
  $(cast az)
echo "Initialized HomeOmnibridge"

echo "Initializing ForeignOmnibridge"
send $FOREIGN_RPC_URL --gas 1000000 $FOREIGN_OB 'initialize(address,address,uint256[3],uint256[2],uint256,address,address)' \
  $FOREIGN_AMB \
  $HOME_OB \
  "[$(cast tw 100),$(cast tw 10),$(cast tw 0.001)]" \
  "[$(cast tw 100),$(cast tw 10)]" \
  1000000 \
  $ADMIN \
  $FOREIGN_FACTORY
echo "Initialized ForeignOmnibridge"

echo "Topping up other addresses"
send $HOME_RPC_URL $ORACLE --value 10000ether
send $HOME_RPC_URL $USER --value 10000ether
send $FOREIGN_RPC_URL $ORACLE --value 10000ether
send $FOREIGN_RPC_URL $USER --value 10000ether

tee ./vars/contracts.env <<EOF
HOME_LIGHT_CLIENT=$HOME_LIGHT_CLIENT
HOME_AMB=$HOME_AMB
HOME_OB=$HOME_OB
HOME_WETH=$HOME_WETH
HOME_ROUTER=$HOME_ROUTER
FOREIGN_LIGHT_CLIENT=$FOREIGN_LIGHT_CLIENT
FOREIGN_AMB=$FOREIGN_AMB
FOREIGN_OB=$FOREIGN_OB
FOREIGN_WETH=$FOREIGN_WETH
FOREIGN_ROUTER=$FOREIGN_ROUTER
EOF
