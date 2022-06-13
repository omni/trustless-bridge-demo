# Trustless Bridge Demo

This repo implements a full setup for a duplex arbitrary message bridge between two post-merge EVM networks.
This bridge works in a trustless manner, by sequentially verifying the beacon block headers in accordance with the Altair light client specification.

## Components
### Contracts
* `contracts/light_client/LightClient.sol` - Contract responsible for verification of beacon block headers according to spec.
* `contracts/amb/TrustlessAMB.sol` - Contract responsible for transmission of messages between two networks.
Messages are being recorded in state mapping, so that the can be later proven on the other side through the Merkle-Patricia proof verification.
* `contracts/omnibridge/{Home,Foreign}Omnibridge.sol` - Modified version of Omnibridge AMB mediator, see https://github.com/omni/omnibridge.git
### Infrastructure
* EVM layer - Modified go-ethereum with enabled BLS EIP2537 precompiles.
* Beacon layer - 2 Lighthouse BN + VC for each side with 512 validators.
* Merge - configured to happen at slot 0 in the beacon chain, TTD is 1000 (~500 block in EVM).
### Oracles
* Light client updater - `./oracle` - worker responsible for generating Light Client proofs and their on-chain execution.
* AMB executor - `./executor` - worker for executing sent AMB messages.

## Scripts
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
* 1 Geth with enabled BLS opcodes, TTD 1000
* 1 Lighthouse Bootnode
* 2 Lighthouse Beacon Nodes
* 2 Lighthouse Validator Clients with 512 validators each

The genesis event will happen in ~2 minutes after the script completion.
Please check the logs of `lh-home-1`/`lh-foreign-1` containers to see the progress.
The merge with the EVM layer will happen on the ~500 EL block number.

Home JSON RPC: `http://localhost:8545`
Foreign JSON RPC: `http://localhost:9545`
Home BN API `http://localhost:5052`
Foreign BN API `http://localhost:6052`

### Deploy contracts
This script deploys and initializes all necessary smart contract on both networks: Light clients, AMB, Omnibridge.
```shell
./scripts/setup.sh
```
Deployed contract addresses are written to `./vars/contracts.json` after deployment.
All scripts below will automatically use this file for gathering relevant contract addresses.

### Send tokens through Omnibridge + AMB
These scripts simply send 1 ETH through the following set of contracts: `WETHOmnibridgeRouter -> {Home,Foreign}Omnibridge -> TrustlessAMB`
```shell
./scripts/send_home_to_foreign.sh
./scripts/send_foreign_to_home.sh
```

### Execute sent message
These scripts execute sent message: `TrustlessAMB -> LightClient + {Home,Foreign}Omnibridge -> WETH`
The given argument is the sent message nonce (incremented by one with each sent message).
```shell
./scripts/execute_home_to_foreign.sh 0
./scripts/execute_foreign_to_home.sh 0
```

In order to execute the message, you must first wait until the far enough block header is verified by the Light Client worker.
The script will print an error, if current block header is not enough.
Typically, the message can be executed within ~2.5 epochs since it was sent (~4 minutes).
