#!/bin/bash

set -e

source ./vars/vars.env
source ./vars/contracts.env

docker stop {home,foreign}-{postgres,blockscout} 2>/dev/null || true
docker rm {home,foreign}-{postgres,blockscout} 2>/dev/null || true

docker run --rm -d --network home --name home-postgres -p 5432:5432 \
  -e POSTGRES_DB=blockscout \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  postgres:14-alpine
docker run --rm -d --network foreign --name foreign-postgres -p 5433:5432 \
  -e POSTGRES_DB=blockscout \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  postgres:14-alpine

sleep 5

docker run --rm -d --network home --name home-blockscout -p 4001:4000 \
  -e ETHEREUM_JSONRPC_VARIANT=geth \
  -e ETHEREUM_JSONRPC_HTTP_URL=$HOME_RPC_URL_DOCKER \
  -e DATABASE_URL=postgresql://postgres:@home-postgres:5432/blockscout?ssl=false \
  -e ECTO_USE_SSL=false \
  -e COIN=ETH \
  -e NETWORK=Home \
  -e SUBNETWORK=Home \
  -e LOGO=/images/blockscout_logo.svg \
  -e LOGO_FOOTER=/images/blockscout_logo.svg \
  -e SUPPORTED_CHAINS='[{"title": "Home", "url": "http://localhost:4001"}, {"title": "Foreign", "url": "http://localhost:4002"}]' \
  $BLOCKSCOUT_IMAGE /bin/sh -c "mix do ecto.create, ecto.migrate && mix phx.server" 2>/dev/null || true
docker run --rm -d --network foreign --name foreign-blockscout -p 4002:4000 \
  -e ETHEREUM_JSONRPC_VARIANT=geth \
  -e ETHEREUM_JSONRPC_HTTP_URL=$FOREIGN_RPC_URL_DOCKER \
  -e DATABASE_URL=postgresql://postgres:@foreign-postgres:5432/blockscout?ssl=false \
  -e ECTO_USE_SSL=false \
  -e COIN=ETH \
  -e NETWORK=Foreign \
  -e SUBNETWORK=Foreign \
  -e LOGO=/images/blockscout_logo.svg \
  -e LOGO_FOOTER=/images/blockscout_logo.svg \
  -e SUPPORTED_CHAINS='[{"title": "Home", "url": "http://localhost:4001"}, {"title": "Foreign", "url": "http://localhost:4002"}]' \
  $BLOCKSCOUT_IMAGE /bin/sh -c "mix do ecto.create, ecto.migrate && mix phx.server" 2>/dev/null || true
