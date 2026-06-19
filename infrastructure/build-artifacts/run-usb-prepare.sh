#!/bin/bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# run-usb-prepare.sh — Build the usb-prepare image (once) and run bootable-usb-prepare.sh inside it.
#
# Supports: Ubuntu, RHEL/Fedora/CentOS, and any distro with Docker or Podman installed.
# On RHEL-based systems Podman is used automatically if Docker is not present.
#
# Usage:
#   sudo ./run-usb-prepare.sh <usb-device> <usb-bootable-files.tar.gz> <config-file> [image.raw.gz]
#
# Example:
#   sudo ./run-usb-prepare.sh /dev/sdX usb-bootable-files.tar.gz config-file
#   sudo ./run-usb-prepare.sh /dev/sdX usb-bootable-files.tar.gz config-file myimage.raw.gz
#
# ─── WSL2 (Windows Subsystem for Linux 2) ──────────────────────────────────────
# WSL2 does not expose USB block devices by default. Attach the USB drive to the
# WSL2 VM first using usbipd-win (one-time setup per session), then run this script
# normally from within WSL2.
#
# Step 1 — Install usbipd-win on Windows (run once):
#   winget install usbipd
#
# Step 2 — From an elevated Windows PowerShell, find and bind the USB drive:
#   usbipd list
#   usbipd bind --busid <busid>
#
# Step 3 — Attach the USB drive to WSL2 (repeat after each Windows reboot):
#   usbipd attach --wsl --busid <busid>
#
# Step 4 — Inside WSL2, confirm the device is visible, then run this script:
#   lsblk          # locate the USB device, e.g. /dev/sdX
#   sudo ./run-usb-prepare.sh /dev/sdX usb-bootable-files.tar.gz config-file
#
# Step 5 — Detach when done (optional):
#   usbipd detach --busid <busid>
# ───────────────────────────────────────────────────────────────────────────────

set -euo pipefail

IMAGE_NAME="usb-prepare-image"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Run this script with sudo."
    exit 1
fi

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "Usage: sudo $0 <usb-device> <usb-bootable-files.tar.gz> <config-file> [image.raw.gz]"
    exit 1
fi

USB_DEVICE="$1"

# Detect container runtime: prefer docker, fall back to podman (common on RHEL/Fedora)
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    RUNTIME="docker"
elif command -v podman &>/dev/null; then
    RUNTIME="podman"
else
    echo "Error: Neither Docker nor Podman is available or running on this system."
    echo "  Ubuntu/Debian: sudo apt install docker.io"
    echo "  RHEL/Fedora:   sudo dnf install podman"
    exit 1
fi

echo "Using container runtime: $RUNTIME"

# Build the container image if it does not exist yet.
# Proxy build-args are forwarded so apt-get can reach the internet
# when the host is behind a corporate firewall.
if ! $RUNTIME image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    echo "Building $IMAGE_NAME (first run only)..."
    $RUNTIME build \
        --build-arg HTTP_PROXY="${HTTP_PROXY:-}" \
        --build-arg HTTPS_PROXY="${HTTPS_PROXY:-}" \
        --build-arg NO_PROXY="${NO_PROXY:-}" \
        --build-arg http_proxy="${http_proxy:-}" \
        --build-arg https_proxy="${https_proxy:-}" \
        --build-arg no_proxy="${no_proxy:-}" \
        -f "$SCRIPT_DIR/Dockerfile.usb-prepare" \
        -t "$IMAGE_NAME" \
        "$SCRIPT_DIR"
fi

# Pass all script arguments through; mount the current working directory as /work
# so the container sees usb-bootable-files.tar.gz, config-file, and any image.raw.gz
# exactly as they appear to the user — matching direct script invocation behaviour.
# -it allocates a pseudo-TTY and connects stdin so progress bar and read prompts work.
# Proxy env vars are forwarded at runtime so the inner script's proxy check passes.
$RUNTIME run --rm \
    --privileged \
    -it \
    --device="$USB_DEVICE" \
    --env HTTP_PROXY="${HTTP_PROXY:-}" \
    --env HTTPS_PROXY="${HTTPS_PROXY:-}" \
    --env NO_PROXY="${NO_PROXY:-}" \
    --env http_proxy="${http_proxy:-}" \
    --env https_proxy="${https_proxy:-}" \
    --env no_proxy="${no_proxy:-}" \
    -v "$PWD":/work \
    "$IMAGE_NAME" \
    "$@"
