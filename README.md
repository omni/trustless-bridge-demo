# Trustless Bridge Demo

This repo implements a full setup for a duplex arbitrary message bridge between two post-merge EVM networks.
This bridge works in a trustless manner, by sequentially verifying the beacon block headers in accordance with the Altair light client specification.

## Components
### Contracts
* `contracts/light_client/BeaconLightClient.sol` - Contract responsible for verification of beacon block headers according to spec.
* `contracts/light_client/LightClientChain.sol` - Contract responsible for verification of execution layer block headers based on the data synced by beacon light client.
* `contracts/amb/TrustlessAMB.sol` - Contract responsible for transmission of messages between two networks.
Messages are being recorded in state mapping, so that the can be later proven on the other side through the Merkle-Patricia proof verification.
* `contracts/omnibridge/{Home,Foreign}Omnibridge.sol` - Modified version of Omnibridge AMB mediator, see https://github.com/omni/omnibridge.git
### Infrastructure
* EVM layer - Modified go-ethereum with enabled BLS EIP2537 precompiles.
* Beacon layer - 2 Lighthouse BN + VC for each side with 512 validators.
* Merge - configured to happen at slot 0 in the beacon chain, TTD is 300 (~150 block in EVM).
### Oracles
* Light client updater - `./oracle/cmd/light_client/worker` - worker responsible for generating Light Client proofs and their on-chain execution.
* Light client chain prover - `./oracle/cmd/light_client_chain/prove` - script for proving full EL block structures in the EVM.
* Light client chain status - `./oracle/cmd/light_client_chain/status` - script for checking sync status of the particular EL block.
* AMB executor - `./oracle/cmd/amb/execute_storage` - worker for executing sent AMB messages through storage verification.
* AMB executor - `./oracle/cmd/amb/execute_log` - worker for executing sent AMB messages through emitted log verification.

## Demo Scripts

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
./scripts/setup.sh
```
Deployed contract addresses are written to `./vars/contracts.env` after deployment.
All scripts below will automatically use this file for gathering relevant contract addresses.

### Send tokens through Omnibridge + AMB
These scripts simply send 1 ETH through the following set of contracts: `WETHOmnibridgeRouter -> {Home,Foreign}Omnibridge -> TrustlessAMB`
```shell
./scripts/send_home_to_foreign.sh
./scripts/send_foreign_to_home.sh
```

### Verify Execution Payload for further AMB executions
These scripts verify latest ExecutionPayloadHeader of the opposite chain, based on the synced data from the LightClient contracts.
```shell
./scripts/prove_home_to_foreign.sh
./scripts/prove_foreign_to_home.sh
```

You can verify ExecutionPayloadHeader of the specific beacon slot using the following:
```shell
./scripts/prove_home_to_foreign.sh <slot_number>
./scripts/prove_foreign_to_home.sh <slot_number>
```

You can also verify ExecutionPayloadHeader of the earlier beacon slot, within (<slot_number>-8191,<slot_number>-1) slot range,
in case requested slot was not part of the LightClient sync process:
```shell
./scripts/prove_home_to_foreign.sh <slot_number> <target_slot_number>
./scripts/prove_foreign_to_home.sh <slot_number> <target_slot_number>
```
Such transitively verified blocks might be useful for accessing receipts_root/transactions_root of the specific block, or accessing non-latest storage state.

### Execute sent message
These scripts execute sent message: `TrustlessAMB -> LightClientChain + {Home,Foreign}Omnibridge -> WETH`
The given argument is the sent message nonce (incremented by one with each sent message).
```shell
./scripts/execute_home_to_foreign.sh 0
./scripts/execute_foreign_to_home.sh 0
```

### Check status of the particular block synchronization
Once you have sent some message that was included in some block on the execution layer side, you may track its sync progress via the command below.
It will print few usefull numbers:
* Slot number of the beacon block associated with the requested EL block
* Slot number of the beacon block where the previous block was finalized
* Current synced slot of the light client on the other side
* Latest verified EL payload block in the LightClientChain contract on the other side
```shell
./scripts/status_home_to_foreign.sh <block_number>
./scripts/status_foreign_to_home.sh <block_number>
```

In order to execute the message, you must first wait until the far enough block header is verified by the Light Client worker.
The script will print an error, if current block header is not enough.
Typically, the message can be executed within ~2.5 epochs since it was sent (~4 minutes).
