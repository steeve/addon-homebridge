#!/bin/bash
set -e

SLUG="homebridge"
BUILD_CONTAINER_NAME="hassioaddons-$SLUG-$$"
LOCAL_REPOSITORY="."
BUILD_DIR="$(pwd)/build"
DOCKER_PUSH="true"
DOCKER_CACHE="true"
DOCKER_WITH_LATEST="true"

cleanup() {
    echo "[INFO] Cleanup."

    # Stop docker container
    echo "[INFO] Cleaning up hassio-build container."
    docker stop $BUILD_CONTAINER_NAME 2> /dev/null || true
    docker rm --volumes $BUILD_CONTAINER_NAME 2> /dev/null || true

    if [ "$1" == "fail" ]; then
        exit 1
    fi
}
trap 'cleanup fail' SIGINT SIGTERM

help () {
    cat << EOF
Script for hassio addon docker build
build [options]

Options:
    -h, --help
        Display this help and exit.
    -a, --arch armhf|aarch64|i386|amd64
        Arch for addon build.
    -t, --test
        Don't upload the build to docker hub.
    -n, --no-cache
        Disable build from cache
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    key=$1
    case $key in
        -h|--help)
            help
            exit 0
            ;;
        -a|--arch)
            ARCH=$2
            shift
            ;;
        -t|--test)
            DOCKER_PUSH="false"
            ;;
        -n|--no-cache)
            DOCKER_CACHE="false"
            ;;
        *)
            echo "[WARNING] $0 : Argument '$1' unknown. Ignoring."
            ;;
    esac
    shift
done

# Sanity checks
if [ "$ARCH" != 'armhf' ] && [ "$ARCH" != 'aarch64' ] && [ "$ARCH" != 'i386' ] && [ "$ARCH" != 'amd64' ]; then
    echo "Error: $ARCH is not a supported platform for hassio-supervisor!"
    help
    exit 1
fi
if [ -z "$SLUG" ]; then
    echo "[ERROR] please set a slug!"
    help
    exit 1
fi

BASE_IMAGE="homeassistant\/$ARCH-base:latest"
DOCKER_IMAGE="steeve/$SLUG-$ARCH"
WORKSPACE=$BUILD_DIR/hassio-supervisor-$ARCH
ADDON_WORKSPACE=$WORKSPACE/$SLUG

# setup docker
echo "[INFO] cleanup old WORKSPACE"
rm -rf "$ADDON_WORKSPACE"

echo "[INFO] Setup docker for addon"
mkdir -p "$BUILD_DIR"
mkdir -p "$WORKSPACE"
cp -r "$LOCAL_REPOSITORY/$SLUG" "$ADDON_WORKSPACE"

# Init docker
echo "[INFO] Setup dockerfile"

sed -i "s/{arch}/${ARCH}/g" "$ADDON_WORKSPACE/config.json"
DOCKER_TAG=$(jq --raw-output ".version" "$ADDON_WORKSPACE/config.json")

# Replace hass.io vars
sed -i "s/%%BASE_IMAGE%%/${BASE_IMAGE}/g" "$ADDON_WORKSPACE/Dockerfile"
sed -i "s/#${ARCH}:FROM/FROM/g" "$ADDON_WORKSPACE/Dockerfile"
sed -i "s/%%ARCH%%/${ARCH}/g" "$ADDON_WORKSPACE/Dockerfile"
echo "LABEL io.hass.version=\"$DOCKER_TAG\" io.hass.arch=\"$ARCH\" io.hass.type=\"addon\"" >> "$ADDON_WORKSPACE/Dockerfile"

# Run build
echo "[INFO] start docker build"
docker stop $BUILD_CONTAINER_NAME 2> /dev/null || true
docker rm --volumes $BUILD_CONTAINER_NAME 2> /dev/null || true
docker run --rm \
    -v "$ADDON_WORKSPACE":/docker \
    -v ~/.docker:/root/.docker \
    -e DOCKER_PUSH=$DOCKER_PUSH \
    -e DOCKER_CACHE=$DOCKER_CACHE \
    -e DOCKER_WITH_LATEST=$DOCKER_WITH_LATEST \
    -e DOCKER_IMAGE="$DOCKER_IMAGE" \
    -e DOCKER_TAG="$DOCKER_TAG" \
    --name $BUILD_CONTAINER_NAME \
    --privileged \
    homeassistant/docker-build-env \
    /run-docker.sh

echo "[INFO] cleanup WORKSPACE"
cd "$BUILD_DIR"
rm -rf "$WORKSPACE"

cleanup "okay"
exit 0
