#!/bin/bash

function build_and_push {
    TAGS=("danuk/shm-$1:latest")

    [ -z "$VERSION" ] && VERSION=$(git tag --points-at | head -n1)
    if [ "$VERSION" ]; then
        TAGS+=("$REPO/shm-$1:$VERSION")
    fi

    docker build \
        $(printf " -t %s" "${TAGS[@]}") \
        --target $1 .

    for TAG in ${TAGS[*]}; do
        docker push $TAG
    done
}

# Build API
build_and_push api

# Build Core
[ -z "$VERSION" ] && VERSION=$(git describe --abbrev=0 --tags)
echo -n "$VERSION" > app/version
build_and_push core

