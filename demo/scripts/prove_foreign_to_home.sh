#!/bin/bash

set -e

source ./vars/vars.env
source ./vars/contracts.env

START_SLOT=${1:-0}
TARGET_SLOT=${2:-$START_SLOT}
id=$(docker create -v $(pwd)/vars/keys:/tmp/keys --entrypoint ./light_client_chain/prove $WORKER_IMAGE \
  --sourceBeaconRPC $FOREIGN_BN_URL_DOCKER \
  --targetRPC $HOME_RPC_URL_DOCKER \
  --lightClientContract $HOME_LIGHT_CLIENT \
  --chainContract $HOME_LIGHT_CLIENT_CHAIN \
  --keystore /tmp/keys/key_user.json \
  --keystorePass '' \
  --startSlot $START_SLOT \
  --targetSlot $TARGET_SLOT)
docker network connect home $id
docker network connect foreign $id
docker start $id
docker logs -f $id
