#!/bin/bash

set -e

source ./vars/vars.env
source ./vars/contracts.env

id=$(docker create -v $(pwd)/vars/keys:/tmp/keys $EXECUTOR_IMAGE \
  --sourceRpc $FOREIGN_RPC_URL_DOCKER \
  --targetRpc $HOME_RPC_URL_DOCKER \
  --sourceAmb $FOREIGN_AMB \
  --targetAmb $HOME_AMB \
  --targetLc $HOME_LIGHT_CLIENT \
  --keystore /tmp/keys/key_user.json \
  --keystorePass '' \
  --msgNonce $1)
docker network connect home $id
docker network connect foreign $id
docker start $id
docker logs -f $id
