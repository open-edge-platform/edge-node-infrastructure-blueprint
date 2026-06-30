#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

#########################################################################
# Boot the installed VEN disk image with SSH port forwarding for testing.
# After ven-deployment.sh completes installation, this script boots the
# installed ubuntu-disk.img with a hostfwd so tests can SSH in.
#########################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VM_DISK="${1:-${SCRIPT_DIR}/../infrastructure/build-artifacts/out/ubuntu-disk.img}"
SSH_HOST_PORT="${2:-2222}"
VNC_DISPLAY="${3:-98}"
VM_MEMORY="${4:-4G}"
BOOT_TIMEOUT="${5:-180}"  # seconds to wait for SSH to become available

if [ ! -f "$VM_DISK" ]; then
    echo "ERROR: VM disk not found: $VM_DISK"
    exit 1
fi

echo "=== Booting VEN for Testing ==="
echo "  Disk: $VM_DISK"
echo "  SSH:  localhost:${SSH_HOST_PORT}"
echo "  VNC:  :${VNC_DISPLAY}"

# Kill any existing test VM
pkill -f "qemu-system-x86_64.*ven-test-vm" 2>/dev/null || true
sleep 2

# Launch VM with SSH port forwarding (daemonized)
qemu-system-x86_64 \
    -name ven-test-vm \
    -m "$VM_MEMORY" \
    -enable-kvm \
    -cpu host \
    -machine q35,accel=kvm \
    -bios /usr/share/qemu/OVMF.fd \
    -vnc ":${VNC_DISPLAY}" \
    -drive "file=${VM_DISK},format=qcow2" \
    -nic "user,hostfwd=tcp::${SSH_HOST_PORT}-:22" \
    -nographic \
    -daemonize \
    -pidfile /tmp/ven-test-vm.pid

echo "VM launched (PID: $(cat /tmp/ven-test-vm.pid 2>/dev/null || echo 'unknown'))"

# Wait for SSH to become available
echo "Waiting for SSH on port ${SSH_HOST_PORT}..."
ELAPSED=0
while ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p "$SSH_HOST_PORT" user@localhost "echo ready" 2>/dev/null; do
    if [ $ELAPSED -ge $BOOT_TIMEOUT ]; then
        echo "ERROR: SSH not available after ${BOOT_TIMEOUT}s"
        exit 1
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    echo "  Waiting... (${ELAPSED}s)"
done

echo "SSH is ready on localhost:${SSH_HOST_PORT}"
