#!/bin/bash

set -e

HOME_RPC_URL=http://geth-home:8545
FOREIGN_RPC_URL=http://geth-foreign:8545
HOME_BN_URL=http://lh-home-1:5052
FOREIGN_BN_URL=http://lh-foreign-1:5052

CONTRACTS=./vars/contracts.json

WORKER_IMAGE=kirillfedoseev/light-client-worker:latest

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

write_config $FOREIGN_RPC_URL $(cat $CONTRACTS | jq -r .foreign.light_client) $HOME_BN_URL > ./vars/config.foreign.yml
write_config $HOME_RPC_URL $(cat $CONTRACTS | jq -r .home.light_client) $FOREIGN_BN_URL > ./vars/config.home.yml

start_worker home-to-foreign-worker $(pwd)/vars/config.foreign.yml 10s
start_worker foreign-to-home-worker $(pwd)/vars/config.home.yml 10s
