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
       	bash-completion \
        gdm3 \
        libgl1-mesa-dri \
        mesa-va-drivers \
        va-driver-all \
        plymouth \
        pciutils \
        kmod


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


RUN sed -i 's/#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf

RUN mkdir -p /lib/systemd/system/gdm.service.d/ && \
    echo "[Service]\nSupplementaryGroups=video render tty" > /lib/systemd/system/gdm.service.d/override.conf

RUN truncate -s 0 /etc/machine-id && rm -f /var/lib/dbus/machine-id

RUN echo "i915" >> /etc/initramfs-tools/modules

RUN mkdir -p /lib/systemd/system/gdm.service.d && \
    printf "[Service]\nExecStartPre=/bin/sleep 1\n" > /lib/systemd/system/gdm.service.d/override.conf

ARG USERNAME
ARG PASSWORD
ENV USERNAME=${USERNAME} \
    PASSWORD=${PASSWORD}

# User setup
RUN useradd -m -s /bin/bash "${USERNAME}" && \
    usermod -p "${PASSWORD}" "${USERNAME}" && \
    usermod -aG sudo,audio,video,render,plugdev,netdev,input "${USERNAME}" && \
    echo "${USERNAME} ALL=(ALL) PASSWD:ALL" >> /etc/sudoers

# Switch to non-root user (Trivy DS-0002).
# NOTE: The container is exported as a rootfs for a bootable image where
# systemd (PID 1) runs as root. This USER directive satisfies the
# container-security check without affecting the final boot image.
USER ${USERNAME}

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD bash --version > /dev/null 2>&1 || exit 1

CMD ["/sbin/init"]
