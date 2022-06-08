#!/bin/bash

set -e

SPEC_PRESET=mainnet
VALIDATOR_COUNT=1024

GENESIS_DELAY=240
SECONDS_PER_SLOT=3
GENESIS_FORK_VERSION=0x00000000
BN_COUNT=2
DEPOSIT_CONTRACT_ADDRESS=0x8544a851E56c754aae5126104A272CBb646aF5Ed
FEE_RECEIVER_ADDRESS=0x087465d0ddc872fc27901e45c861e6956622eb66
BOOTNODE_PORT=12000

NOW=$(date +%s)
GENESIS_TIME=$(expr $NOW + $GENESIS_DELAY)

HOME_DIR="$(pwd)/data/home"
FOREIGN_DIR="$(pwd)/data/foreign"
GETH_SECRET="$(pwd)/vars/jwtsecret"
GETH_KEYSTORE="$(pwd)/vars/keys"
GETH_IMAGE=kirillfedoseev/geth:v1.10.18-bls-dev-ttd

LCLI_IMAGE=sigp/lcli:v2.3.0
LCLI_HOME="docker run --network home --workdir $(pwd) --rm -v $(pwd):$(pwd) $LCLI_IMAGE lcli"
LCLI_FOREIGN="docker run --network foreign --workdir $(pwd) --rm -v $(pwd):$(pwd) $LCLI_IMAGE lcli"

LH_IMAGE=sigp/lighthouse:v2.3.0-modern

function start_beacon_node() {
    docker run -d --name $6 -p $5:5052 -v $2:$2 -v $3:$3:ro -v $GETH_SECRET:/tmp/jwtsecret --network $1 \
      $LH_IMAGE lighthouse bn \
      --subscribe-all-subnets \
      --datadir $2 \
      --testnet-dir $3 \
      --enable-private-discovery \
      --staking \
      --enr-address $6 \
      --enr-udp-port $4 \
      --enr-tcp-port $4 \
      --port $4 \
      --http-address 0.0.0.0 \
      --http-port 5052 \
      --disable-packet-filter \
      --target-peers $((BN_COUNT - 1)) \
      --terminal-total-difficulty-override 1000 \
      --eth1-endpoints http://geth-$1:8545 \
      --execution-endpoints http://geth-$1:8551 \
      --jwt-secrets /tmp/jwtsecret \
      --merge \
      --suggested-fee-recipient $FEE_RECEIVER_ADDRESS
}

function start_validator_client() {
  docker run -d --name $5 -v $2:$2 -v $3:$3:ro --network $1 \
    $LH_IMAGE lighthouse vc \
    --datadir $2 \
    --testnet-dir $3 \
    --init-slashing-protection \
    --beacon-nodes $4 \
    --suggested-fee-recipient $FEE_RECEIVER_ADDRESS
}

function start_bootnode() {
    echo "Generating bootnode enr"

    docker run --rm -v "$(pwd)/data/$1:/tmp/$1" \
      $LCLI_IMAGE lcli generate-bootnode-enr \
      --ip $4 \
      --udp-port $BOOTNODE_PORT \
      --tcp-port $BOOTNODE_PORT \
      --genesis-fork-version $GENESIS_FORK_VERSION \
      --output-dir /tmp/$1/bootnode

    bootnode_enr=$(cat "$(pwd)/data/$1/bootnode/enr.dat")
    echo "- $bootnode_enr" > $2/boot_enr.yaml

    echo "Generated bootnode enr and written to $2/boot_enr.yaml"

    echo "Starting bootnode"

    docker run -d --name $3 -v $2:$2:ro -v "$(pwd)/data/$1/bootnode:/tmp/bootnode" --network $1 --ip $4 \
      $LH_IMAGE lighthouse boot_node \
      --testnet-dir $2 \
      --port $BOOTNODE_PORT \
      --listen-address 0.0.0.0 \
      --disable-packet-filter \
      --network-dir /tmp/bootnode
}

function start_geth() {
  docker run --network $1 -p $2:8545 --name geth-$1 -d -v $GETH_KEYSTORE:/tmp/keys -v $GETH_SECRET:/tmp/jwtsecret \
    $GETH_IMAGE --dev --networkid $3 \
    --http --http.addr 0.0.0.0 --http.api net,eth,engine,debug --http.vhosts '*' --http.corsdomain '*' \
    --authrpc.port 8551 --authrpc.addr 0.0.0.0 --authrpc.vhosts '*' --authrpc.jwtsecret /tmp/jwtsecret \
    --dev.period $SECONDS_PER_SLOT --gcmode archive \
    --keystore /tmp/keys
}

function prepare_validators() {
  echo "Deploying home deposit contract"
  $1 deploy-deposit-contract --eth1-http http://geth-$2:8545 --confirmations 1 --validator-count $VALIDATOR_COUNT

  $1 new-testnet --spec $SPEC_PRESET \
  	--deposit-contract-address $DEPOSIT_CONTRACT_ADDRESS \
  	--testnet-dir $3/testnet \
  	--min-genesis-active-validator-count $VALIDATOR_COUNT \
  	--min-genesis-time $NOW \
  	--genesis-delay $GENESIS_DELAY \
  	--genesis-fork-version $GENESIS_FORK_VERSION \
  	--altair-fork-epoch 0 \
  	--merge-fork-epoch 0 \
  	--eth1-id $4 \
  	--eth1-follow-distance 1 \
  	--seconds-per-slot $SECONDS_PER_SLOT \
  	--seconds-per-eth1-block $SECONDS_PER_SLOT \
  	--force

  echo Specification generated at $3/testnet.
  echo "Generating $VALIDATOR_COUNT validators concurrently... (this may take a while)"

  $1 insecure-validators --count $VALIDATOR_COUNT --base-dir $3/datadir --node-count $BN_COUNT

  echo Validators generated with keystore passwords at $3/datadir.
  echo "Building genesis state... (this might take a while)"

  $1 interop-genesis --spec $SPEC_PRESET --genesis-time $GENESIS_TIME --testnet-dir $3/testnet $GENESIS_VALIDATOR_COUNT

  echo Created genesis state in $3/testnet
}

docker network create --subnet=192.168.0.0/20 home || true
docker network create --subnet=192.168.16.0/20 foreign || true

start_geth home 8545 1337
start_geth foreign 9545 137

sleep 3

prepare_validators "$LCLI_HOME" home "$HOME_DIR" 1337
prepare_validators "$LCLI_FOREIGN" foreign "$FOREIGN_DIR" 137

start_bootnode home $HOME_DIR/testnet bootnode-home 192.168.0.99
start_bootnode foreign $FOREIGN_DIR/testnet bootnode-foreign 192.168.16.99

start_beacon_node home $HOME_DIR/datadir/node_1 $HOME_DIR/testnet 12000 5052 lh-home-1
start_beacon_node home $HOME_DIR/datadir/node_2 $HOME_DIR/testnet 12000 5053 lh-home-2
start_beacon_node foreign $FOREIGN_DIR/datadir/node_1 $FOREIGN_DIR/testnet 12000 6052 lh-foreign-1
start_beacon_node foreign $FOREIGN_DIR/datadir/node_2 $FOREIGN_DIR/testnet 12000 6053 lh-foreign-2

start_validator_client home $HOME_DIR/datadir/node_1 $HOME_DIR/testnet http://lh-home-1:5052 lh-home-vc-1
start_validator_client home $HOME_DIR/datadir/node_2 $HOME_DIR/testnet http://lh-home-2:5052 lh-home-vc-2
start_validator_client foreign $FOREIGN_DIR/datadir/node_1 $FOREIGN_DIR/testnet http://lh-foreign-1:5052 lh-foreign-vc-1
start_validator_client foreign $FOREIGN_DIR/datadir/node_2 $FOREIGN_DIR/testnet http://lh-foreign-2:5052 lh-foreign-vc-2
