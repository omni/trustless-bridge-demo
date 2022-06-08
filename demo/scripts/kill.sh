#!/bin/bash

set -e

docker stop $(docker ps -a -q) 2>/dev/null || true
docker rm $(docker ps -a -q) 2>/dev/null || true

docker network remove home 2>/dev/null || true
docker network remove foreign 2>/dev/null || true

rm -rf $(pwd)/data/home
rm -rf $(pwd)/data/foreign
