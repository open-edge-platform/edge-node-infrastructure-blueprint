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

# Intel overlay repository override contract.
# Left empty by default — curate-host-packages.sh applies its own public
# defaults (${VAR:-...}) when these are unset/empty. Internal CI can pass
# --build-arg INTEL_OVERLAY_URL=... etc. to validate against a mirror
# without editing the script.
# INTEL_OVERLAY_KEY_FINGERPRINT uses ${VAR-default} in the script, so passing
# an explicit empty string here disables the pin (trusted internal mirror),
# while leaving it unset keeps the public-key fingerprint pin.
ARG INTEL_OVERLAY_URL=""
ARG INTEL_OVERLAY_COMPONENTS=""
ARG INTEL_OVERLAY_KEY_URL=""
ARG INTEL_OVERLAY_KEY_FINGERPRINT

ENV http_proxy=${http_proxy} \
    https_proxy=${https_proxy} \
    no_proxy=${no_proxy} \
    HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    NO_PROXY=${NO_PROXY} \
    INTEL_OVERLAY_URL=${INTEL_OVERLAY_URL} \
    INTEL_OVERLAY_COMPONENTS=${INTEL_OVERLAY_COMPONENTS} \
    INTEL_OVERLAY_KEY_URL=${INTEL_OVERLAY_KEY_URL} \
    INTEL_OVERLAY_KEY_FINGERPRINT=${INTEL_OVERLAY_KEY_FINGERPRINT} \
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

RUN sed -i 's/#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf

RUN mkdir -p /lib/systemd/system/gdm.service.d/ && \
    echo "[Service]\nSupplementaryGroups=video render tty" > /lib/systemd/system/gdm.service.d/override.conf

RUN truncate -s 0 /etc/machine-id && rm -f /var/lib/dbus/machine-id

RUN echo "i915" >> /etc/initramfs-tools/modules

RUN mkdir -p /lib/systemd/system/gdm.service.d && \
    printf "[Service]\nExecStartPre=/bin/sleep 1\n" > /lib/systemd/system/gdm.service.d/override.conf

# User setup
RUN useradd -m -s /bin/bash "${USERNAME}" && \
    usermod -p "${USER_PASSWORD}" "${USERNAME}" && \
    usermod -aG sudo,audio,video,render,plugdev,netdev,input "${USERNAME}" && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

CMD ["/sbin/init"]
