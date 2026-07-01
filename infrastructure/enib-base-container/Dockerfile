# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# syntax=docker/dockerfile:1
# Base builder image with common dependencies for all build containers
FROM ubuntu:24.04

ARG http_proxy
ARG https_proxy
ARG no_proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

ENV http_proxy=${http_proxy} \
    https_proxy=${https_proxy} \
    no_proxy=${no_proxy} \
    HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    NO_PROXY=${NO_PROXY} \
    DEBIAN_FRONTEND=noninteractive

# Configure APT for parallel downloads and install common dependencies
# Using cache mounts for faster subsequent builds
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    echo 'Acquire::http::Pipeline-Depth "10";' > /etc/apt/apt.conf.d/99parallel && \
    echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99no-translations && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        bc \
        ca-certificates \
        cpio \
        curl \
        dialog \
        dosfstools \
        e2fsprogs \
        efibootmgr \
        fdisk \
        gdisk \
        gnupg \
        gzip \
        iproute2 \
        kmod \
        net-tools \
        parted \
        pciutils \
        pigz \
        sudo \
        udev \
        util-linux \
        wget \
        xz-utils
