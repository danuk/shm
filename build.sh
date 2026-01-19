#!/bin/bash

REPO="danuk"

function build_and_push {
    TAGS=()
    for TAG in ${LABELS[*]}; do
        TAGS+=("$REPO/shm-$1:$TAG")
    done

    docker build --platform linux/amd64,linux/arm64 \
        $(printf " -t %s" "${TAGS[@]}") \
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

# Create version.json
COMMIT_SHA=$(git rev-parse HEAD)
cat > app/version.json << EOF
{
    "version": "${GIT_TAG}-${REV}",
    "commitSha": "${COMMIT_SHA}",
    "releaseUrl": "https://github.com/danuk/shm/releases/tag/${GIT_TAG}"
}
EOF
echo "Created app/version.json:"
cat app/version.json

build_and_push api
build_and_push core

