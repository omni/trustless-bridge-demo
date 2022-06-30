#!/bin/bash

set -e

source ./vars/vars.env
source ./vars/contracts.env

id=$(docker create -v $(pwd)/vars/keys:/tmp/keys --entrypoint ./amb/execute_storage $WORKER_IMAGE \
  --sourceRPC $FOREIGN_RPC_URL_DOCKER \
  --targetRPC $HOME_RPC_URL_DOCKER \
  --sourceAMB $FOREIGN_AMB \
  --targetAMB $HOME_AMB \
  --targetLCChain $HOME_LIGHT_CLIENT_CHAIN \
  --keystore /tmp/keys/key_user.json \
  --keystorePass '' \
  --msgNonce $1)
docker network connect home $id
docker network connect foreign $id
docker start $id
docker logs -f $id
