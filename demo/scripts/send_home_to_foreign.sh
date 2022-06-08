#!/bin/bash

set -e

HOME_RPC_URL=http://localhost:8545
FOREIGN_RPC_URL=http://localhost:9545

CONTRACTS=./vars/contracts.json

cast send --keystore $(pwd)/vars/keys/key_user.json --password '' --rpc-url $HOME_RPC_URL --gas 1000000 \
  --value 1ether $(cat $CONTRACTS | jq -r .home.weth_router) 'wrapAndRelayTokens()'
