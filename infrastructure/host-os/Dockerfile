# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# syntax=docker/dockerfile:1
# This Dockerfile is designed to create a host operating system image for edge node infrastructure. It uses Ubuntu 24.04 as the base image and installs essential packages for system initialization, networking, and desktop environment.

FROM ubuntu:24.04 AS host-os-base

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

# Configure APT for optimal performance
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    echo 'Acquire::http::Pipeline-Depth "10";' > /etc/apt/apt.conf.d/99parallel && \
    echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99no-translations && \
    echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/99no-recommends

# Base system: init, networking, boot tooling
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        systemd \
        systemd-sysv \
	systemd-resolved \
        dbus \
        sudo \
        network-manager \
        initramfs-tools \
        software-properties-common \
        gnupg \
        curl \
        grub-efi-amd64-bin \
        grub-efi-amd64-signed \
        shim-signed \
        efibootmgr \
        linux-firmware

# Desktop environment
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    add-apt-repository universe && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        xorg \
        ubuntu-desktop-minimal \
        gnome-terminal \
        bash-completion

# Final image custom-image
FROM host-os-base

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

# Copy and run custom package/kernel installation script
COPY curate-host-packages.sh /usr/local/bin/curate-host-packages.sh
RUN chmod +x /usr/local/bin/curate-host-packages.sh && \
    /usr/local/bin/curate-host-packages.sh && \
    rm -f /usr/local/bin/curate-host-packages.sh

# Enable required services
RUN systemctl --root=/ enable NetworkManager   || true && \
    systemctl --root=/ enable systemd-resolved  || true && \
    systemctl --root=/ enable gdm               || true && \
    systemctl --root=/ set-default graphical.target

ARG USERNAME=user
ARG USER_PASSWORD='$6$ENIBDEFAULT$ldaxPVYnIXySCgfxvzBdUwUw6Kyt5DiGzeDe4brEFEIIe2C1.42Vu5pRg1qH8WfkPYvVohvfyLQY6AeQRcRpx1'



# User setup
RUN useradd -m -s /bin/bash "${USERNAME}" && \
    usermod -p "${USER_PASSWORD}" "${USERNAME}" && \
    usermod -aG sudo,audio,video,render,plugdev,netdev,input "${USERNAME}" && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

CMD ["/sbin/init"]
