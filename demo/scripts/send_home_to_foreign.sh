#!/bin/bash

set -e

source ./vars/vars.env
source ./vars/contracts.env

#cast send --keystore $(pwd)/vars/keys/key_user.json --password '' --rpc-url $HOME_RPC_URL --gas 1000000 \
#  --value 1ether $HOME_ROUTER 'wrapAndRelayTokens()'

HOME_BRIDGED_WETH=$(cast call --rpc-url $HOME_RPC_URL $HOME_OB 'bridgedTokenAddress(address) (address)' $FOREIGN_WETH)

cast send --keystore $(pwd)/vars/keys/key_user.json --password '' --rpc-url $HOME_RPC_URL --gas 1000000 \
  $HOME_BRIDGED_WETH 'transfer(address,uint256)' $HOME_OB $(cast to-unit 1ether)
