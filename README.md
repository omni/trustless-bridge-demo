# Trustless Bridge Demo

This repo implements a full setup for a duplex arbitrary message bridge between two post-merge EVM networks.
This bridge works in a trustless manner, by sequentially verifying the beacon block headers in accordance with the Altair light client specification.

## Components
### Contracts
* `contracts/light_client/BeaconLightClient.sol` - Contract responsible for verification of beacon block headers according to spec.
* `contracts/amb/TrustlessAMB.sol` - Contract responsible for transmission of messages between two networks.
Messages are being recorded in state mapping, so that the can be later proven on the other side through the Merkle-Patricia proof verification.
* `contracts/omnibridge/{Home,Foreign}Omnibridge.sol` - Modified version of Omnibridge AMB mediator, see https://github.com/omni/omnibridge.git
### Infrastructure
* EVM layer - Modified go-ethereum with enabled BLS EIP2537 precompiles.
* Beacon layer - 2 Lighthouse BN + VC for each side with 512 validators.
* Merge - configured to happen at slot 0 in the beacon chain, TTD is 300 (~150 block in EVM).
### Oracles
* Light client updater - `./oracle/cmd/light_client/worker` - worker responsible for generating Light Client proofs and their on-chain execution.
* AMB executor - `./oracle/cmd/amb/execute_storage` - worker for executing sent AMB messages through storage verification.
* AMB executor - `./oracle/cmd/amb/execute_log` - worker for executing sent AMB messages through emitted log verification.

## Demo Video
To get a better understanding of what's going on here and how the bridge works in practice, check out a short demo video - https://youtu.be/VoXDHe5wetE

## Running Demo Locally

### Requirements
In order to execute demo scripts, make sure the following requirements are installed on your host:
* bash
* docker
* docker-compose
* forge & cast tools (https://book.getfoundry.sh/getting-started/installation.html)
* jq (https://stedolan.github.io/jq/download/)

### Switch directory
Before running any of the below scripts, change your working dir to `./demo`:
```shell
cd ./demo
```

### Clean docker containers
This script will kill and remove all docker containers, remove all generated data.
```shell
./scripts/kill.sh
```

### Setup infrastructure
This script will launch two independent ETH networks.
All containers are associated either with `home` or `foreign` docker bridge networks.
```shell
./scripts/setup.sh
```

For each network, the following infrastructure is being launched:
* 1 Geth with enabled BLS opcodes, TTD 300
* 1 Lighthouse Bootnode
* 2 Lighthouse Beacon Nodes
* 2 Lighthouse Validator Clients with 512 validators each

The genesis event will happen in ~2 minutes after the script completion.
Please check the logs of `lh-home-1`/`lh-foreign-1` containers to see the progress.
The merge with the EVM layer will happen on the ~150 EL block number.

Home JSON RPC: `http://localhost:8545`
Foreign JSON RPC: `http://localhost:9545`
Home BN API `http://localhost:5052`
Foreign BN API `http://localhost:6052`

### Deploy contracts
This script deploys and initializes all necessary smart contract on both networks: Light clients, AMB, Omnibridge.
```shell
./scripts/deploy.sh
```
Deployed contract addresses are written to `./vars/contracts.env` after deployment.
All scripts below will automatically use this file for gathering relevant contract addresses.

### Start Light Client workers
This script will launch a pair of oracles that will periodically generate and sumbit light client updates on-chain.
```shell
./scripts/start_light_client_workers.sh
```

### Send tokens through Omnibridge + AMB
These scripts simply send 1 ETH through the following set of contracts: `WETHOmnibridgeRouter -> {Home,Foreign}Omnibridge -> TrustlessAMB`
```shell
./scripts/send_home_to_foreign.sh
./scripts/send_foreign_to_home.sh
```

### Execute sent message
These scripts execute sent message: `TrustlessAMB -> BeacinLightClient + {Home,Foreign}Omnibridge -> WETH`
The given argument is the sent message nonce (incremented by one with each sent message).
```shell
./scripts/execute_home_to_foreign.sh 0
./scripts/execute_foreign_to_home.sh 0
```

### Launch Blockscout
For better understanding of what is going on, you can quickly launch two Blockscout instances for both networks and see all events and transactions there.
```shell
./scripts/start_explorers.sh
```
Home network explorer will be available at `http://localhost:4001`.
Foreign network explorer will be available at `http://localhost:4002`.

Once explorers will be ready to use, you can conveniently verify all deployed contracts:
```shell
./scripts/verify_contracts.sh
```

