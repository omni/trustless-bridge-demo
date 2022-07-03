#!/bin/bash

set -e

source ./vars/vars.env
source ./vars/contracts.env

id=$(docker create -v $(pwd)/vars/keys:/tmp/keys --entrypoint ./light_client_chain/status $WORKER_IMAGE \
  --sourceBeaconRPC $FOREIGN_BN_URL_DOCKER \
  --targetRPC $HOME_RPC_URL_DOCKER \
  --lightClientContract $HOME_LIGHT_CLIENT \
  --chainContract $HOME_LIGHT_CLIENT_CHAIN \
  --blockNumber $1)
docker network connect home $id
docker network connect foreign $id
docker start $id
docker logs -f $id
