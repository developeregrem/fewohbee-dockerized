#!/bin/sh

dockerBin=$(which docker)
if [ $? -ne 0 ]; then
    echo "Docker must be installed!"
    exit 1
fi
dockerComposeBin="$dockerBin compose"

# remove network, volumes and container
$dockerComposeBin down -v