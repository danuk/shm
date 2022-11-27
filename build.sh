#!/bin/bash

VERSION=$(git tag --points-at | head -n1)

if [ -z "$VERSION" ]; then
    echo "Error: tag required"
fi

VERSION_MINOR=$(echo $VERSION | cut -d '.' -f 1,2)

function build_and_push {
    TAGS=(
        danuk/shm-$1:$VERSION
        danuk/shm-$1:$VERSION_MINOR
        danuk/shm-$1
    )

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

