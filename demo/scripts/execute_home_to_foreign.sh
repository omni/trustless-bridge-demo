#!/bin/bash

set -e

source ./vars/vars.env
source ./vars/contracts.env

id=$(docker create -v $(pwd)/vars/keys:/tmp/keys --entrypoint ./amb/execute_log $WORKER_IMAGE \
  --sourceBeaconRPC $HOME_BN_URL_DOCKER \
  --sourceRPC $HOME_RPC_URL_DOCKER \
  --targetRPC $FOREIGN_RPC_URL_DOCKER \
  --sourceAMB $HOME_AMB \
  --targetAMB $FOREIGN_AMB \
  --targetLC $FOREIGN_LIGHT_CLIENT \
  --keystore /tmp/keys/key_user.json \
  --keystorePass '' \
  --msgNonce $1)
docker network connect home $id
docker network connect foreign $id
docker start $id
docker logs -f $id
