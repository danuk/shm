#!/bin/bash

function build_and_push {
    TAGS=("danuk/shm-$1:latest")

    VERSION=$(git tag --points-at | head -n1)
    if [ "$VERSION" ]; then
        TAGS+=("danuk/shm-$1:$VERSION")

        VERSION_MINOR=$(echo $VERSION | cut -d '.' -f 1,2)
        TAGS+=("danuk/shm-$1:$VERSION_MINOR")
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
echo -n "$VERSION" > app/version
build_and_push core

