#!/bin/bash

set -e

source ./vars/vars.env
source ./vars/contracts.env

function write_config() {
  cat <<EOF
eth1:
  client:
    url: "$1"
  contract: "$2"
  keystore: /tmp/keys/key_oracle.json
  keystore_password: ''
eth2:
  client:
    url: "$3"
EOF
}

function start_worker() {
  id=$(docker create --name $1 -v $2:/tmp/config.yml -v $(pwd)/vars/keys:/tmp/keys $WORKER_IMAGE --config /tmp/config.yml --interval $3)
  docker network connect home $id
  docker network connect foreign $id
  docker start $id
}

docker stop home-to-foreign-worker foreign-to-home-worker 2>/dev/null || true
docker rm home-to-foreign-worker foreign-to-home-worker 2>/dev/null || true

write_config $FOREIGN_RPC_URL_DOCKER $FOREIGN_LIGHT_CLIENT $HOME_BN_URL_DOCKER > ./vars/config.foreign.yml
write_config $HOME_RPC_URL_DOCKER $HOME_LIGHT_CLIENT $FOREIGN_BN_URL_DOCKER > ./vars/config.home.yml

start_worker home-to-foreign-worker $(pwd)/vars/config.foreign.yml 10s
start_worker foreign-to-home-worker $(pwd)/vars/config.home.yml 10s
