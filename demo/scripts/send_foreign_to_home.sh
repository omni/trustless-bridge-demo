#!/bin/bash

set -e

source ./vars/vars.env
source ./vars/contracts.env

cast send --keystore $(pwd)/vars/keys/key_user.json --password '' --rpc-url $FOREIGN_RPC_URL --gas 1000000 \
  --value 1ether $FOREIGN_ROUTER 'wrapAndRelayTokens()'
