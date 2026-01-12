#!/bin/bash

REPO="danuk"

function build_and_push {
    TAGS=()
    for TAG in ${LABELS[*]}; do
        TAGS+=("$REPO/shm-$1:$TAG")
    done

    docker build --platform linux/amd64,linux/arm64 \
        $(printf " -t %s" "${TAGS[@]}") \
        -f Dockerfile-base \
        --target $1 .

    for TAG in ${TAGS[*]}; do
        docker push $TAG
    done
}

# Set tag from git
GIT_TAG=$(git describe --abbrev=0 --tags)
LABELS=("$GIT_TAG")

# Add minor tag
VERSION_MINOR=$(echo $GIT_TAG | cut -d '.' -f 1,2)
LABELS+=("$VERSION_MINOR")

# Add custom tags
LABELS+=("$@")

REV=$(git rev-parse --short HEAD)
echo "Build version: ${GIT_TAG}-${REV}"
echo "TAGS: ${LABELS[@]}"

read -p "Press enter to continue..."
echo -n "${GIT_TAG}-${REV}" > app/version

build_and_push api
build_and_push core-base
build_and_push webdav

