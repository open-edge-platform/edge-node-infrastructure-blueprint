#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

#########################################################################
# VEN Cleanup - Shutdown test VM and clean up resources.
#########################################################################
set -euo pipefail

SSH_PORT="${1:-2222}"
SSH_USER="${2:-user}"
SSH_HOST="${3:-localhost}"
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${SSH_PORT}"

echo "=== VEN Cleanup ==="

# Graceful shutdown via SSH
echo "Attempting graceful shutdown..."
# shellcheck disable=SC2086
ssh $SSH_OPTS "${SSH_USER}@${SSH_HOST}" "sudo shutdown -h now" 2>/dev/null || true
sleep 5

# Force kill if still running
if pgrep -f "qemu-system-x86_64.*ven-test-vm" > /dev/null 2>&1; then
    echo "Force killing test VM..."
    pkill -f "qemu-system-x86_64.*ven-test-vm" || true
fi

# Clean PID file
rm -f /tmp/ven-test-vm.pid

echo "Cleanup complete."
