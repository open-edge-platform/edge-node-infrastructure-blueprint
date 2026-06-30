# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# syntax=docker/dockerfile:1
# Use the optimized base image with common dependencies
FROM edge-base-builder:ubuntu24.04 AS base

# Build-artifacts specific packages layer
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        grub-efi-amd64-bin \
        grub2-common \
        kpartx \
        lsb-release \
        mtools \
        xorriso

# Add Docker CLI in separate layer (changes less frequently)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-buildx-plugin

WORKDIR /workspace

# Entrypoint that runs the build orchestrator
# CMD provides the default mode; overridden by Makefile's "$(MODE)" "$(ICT_IMG)" args
ENTRYPOINT ["/workspace/infrastructure/build-artifacts/build-installation-artifacts.sh"]
CMD ["standard-image"]
