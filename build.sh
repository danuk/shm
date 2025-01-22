#!/bin/bash

REPO="danuk"

function build_and_push {
    TAGS=("$REPO/shm-$1:$GIT_TAG" "$REPO/shm-$1:$REV")

    docker build --platform linux/amd64,linux/arm64 \
        $(printf " -t %s" "${TAGS[@]}") \
        --target $1 .

    for TAG in ${TAGS[*]}; do
        docker push $TAG
    done
}

GIT_TAG=$(git describe --abbrev=0 --tags)
GIT_COMMIT_SHORT=$(git rev-parse --short HEAD)
REV=${1:-$GIT_COMMIT_SHORT}

echo "Build version: ${GIT_TAG}-${REV}"
read -p "Press enter to continue..."

echo -n "${GIT_TAG}-${REV}" > app/version

build_and_push api
build_and_push core
