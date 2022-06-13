#!/bin/bash

set -e

HOME_RPC_URL=http://geth-home:8545
FOREIGN_RPC_URL=http://geth-foreign:8545

CONTRACTS=./vars/contracts.json

EXECUTOR_IMAGE=kirillfedoseev/trustless-amb-executor

id=$(docker create -v $(pwd)/vars/keys:/tmp/keys $EXECUTOR_IMAGE \
  --sourceRpc $FOREIGN_RPC_URL \
  --targetRpc $HOME_RPC_URL \
  --sourceAmb $(cat $CONTRACTS | jq -r .foreign.amb) \
  --targetAmb $(cat $CONTRACTS | jq -r .home.amb) \
  --targetLc $(cat $CONTRACTS | jq -r .home.light_client) \
  --keystore /tmp/keys/key_user.json \
  --keystorePass '' \
  --msgNonce $1)
docker network connect home $id
docker network connect foreign $id
docker start $id
docker logs -f $id
