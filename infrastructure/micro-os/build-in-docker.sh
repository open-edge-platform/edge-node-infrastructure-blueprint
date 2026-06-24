#!/bin/bash

set -euo pipefail

set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE_TAG="micro-os-builder:ubuntu24.04"
OUTPUT_DIR="$(cd "$SCRIPT_DIR" && pwd)/output"
HOST_REPO_ROOT="${HOST_REPO_ROOT:-}"
if [[ -n "$HOST_REPO_ROOT" ]]; then
    # When invoked from inside another container, docker daemon still resolves
    # bind sources on the host, so use host repo path for the mount source.
    HOST_OUTPUT_DIR="$HOST_REPO_ROOT/infrastructure/micro-os/output"
else
    HOST_OUTPUT_DIR="$OUTPUT_DIR"
fi
IMAGE_REBUILD="${MICRO_OS_REBUILD:-false}"

mkdir -p "$OUTPUT_DIR"

build_args=()
run_envs=()
for proxy_var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
    if [[ -n "${!proxy_var:-}" ]]; then
        build_args+=(--build-arg "$proxy_var=${!proxy_var}")
        run_envs+=(-e "$proxy_var=${!proxy_var}")
    fi
done

cd "$REPO_ROOT"
if [[ "$IMAGE_REBUILD" == "true" ]] || ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    docker build "${build_args[@]}" -f infrastructure/micro-os/Dockerfile -t "$IMAGE_TAG" --build-arg OUTPUT_DIR=/workspace/infrastructure/micro-os/output .
else
    echo "Using cached image: $IMAGE_TAG"
fi

docker run --rm --privileged \
    -e OUT=/workspace/infrastructure/micro-os/output \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    "${run_envs[@]}" \
    -v "$HOST_OUTPUT_DIR":/workspace/infrastructure/micro-os/output \
    "$IMAGE_TAG"

echo "Kernel and Initramfs are available in: $OUTPUT_DIR"
