# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# syntax=docker/dockerfile:1
# Use the optimized base image - all common packages already installed
FROM edge-base-builder:ubuntu24.04

# Micro-OS has no additional packages needed beyond base
# All tools (bash, wget, ca-certificates, cpio, gzip, etc.) are in base

# Copy build scripts and dependencies (put COPY late to leverage cache)
COPY infrastructure/micro-os/build-alpine-os.sh /workspace/infrastructure/micro-os/build-alpine-os.sh
COPY infrastructure/provisioning-scripts /workspace/infrastructure/provisioning-scripts
COPY infrastructure/installation-scripts /workspace/infrastructure/installation-scripts

RUN chmod +x /workspace/infrastructure/micro-os/build-alpine-os.sh

WORKDIR /workspace/infrastructure/micro-os

ENTRYPOINT ["/bin/bash", "-c", "exec /workspace/infrastructure/micro-os/build-alpine-os.sh"]
