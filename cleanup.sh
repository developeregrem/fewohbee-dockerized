#!/bin/sh

dockerComposeBin=$(which docker-compose)

# remove network, volumes and container
$dockerComposeBin down -v