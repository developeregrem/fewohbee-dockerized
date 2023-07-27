#!/bin/bash

cd "$(dirname "$0")"

dockerBin=$(/usr/bin/which docker)
$dockerBin compose pull
$dockerBin compose build --force-rm --pull
$dockerBin compose stop
$dockerBin compose up --force-recreate -d
docker image prune -f
