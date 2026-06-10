#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# container-provision.sh — First-boot provisioning for host_type=container
#
# Called by cloud-init installer.cfg runcmd on the TARGET node after first boot.
# This script expects docker to already be installed (either via
# auto-install-pkgs.yaml for ISO builds or as packages in ICT images).
#
# Responsibilities:
#   - Disable k3s, enable docker
#   - Add edge user to docker group
#   - Wait for Docker daemon readiness
#   - Run hello-world smoke test

set -x

LOG_FILE="/var/log/edge-installer.log"
exec >> "$LOG_FILE" 2>&1

date
echo "=== container-provision.sh: start ==="

# Source proxy and environment variables
. /etc/environment 2>/dev/null || true

# ── Disable and stop k3s — container node does not run kubernetes ─────────
systemctl disable k3s 2>/dev/null || true
systemctl stop k3s 2>/dev/null || true

# ── Enable and start Docker ──────────────────────────────────────────────
# Option 1 (ISO): docker installed by auto-install-pkgs.yaml; may already be running.
# Option 2 (ICT): docker pre-installed as package; needs to be enabled.
# Docker daemon and client proxy are pre-configured by install-os.sh during
# OS installation (systemd drop-in + ~/.docker/config.json).

systemctl daemon-reload
systemctl enable --now docker

# ── Add edge user to docker group ────────────────────────────────────────
EDGE_USER=$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" && $7 !~ /(nologin|false|sync)/ {print $1; exit}' /etc/passwd)
[ -n "$EDGE_USER" ] && usermod -aG docker "$EDGE_USER" || true

# ── Wait for Docker daemon to be ready (up to 60 seconds) ────────────────
echo "Waiting for Docker daemon..."
for i in $(seq 1 30); do
    docker info >/dev/null 2>&1 && break
    sleep 2
done
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon not ready after 60 seconds"
    exit 1
fi
echo "Docker is running: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"

# ── Smoke test: pull and run hello-world ─────────────────────────────────
echo "Running docker hello-world smoke test..."
docker pull hello-world || true
docker run --rm hello-world || true

# ── SR-IOV Configuration (Optional) ───────────────────────────────────────
# Set up SR-IOV virtual functions if enabled in config-file
INSTALL_SCRIPTS="/opt/edge/scripts"
CONFIG_FILE="/etc/cloud/config-file"
if [ -f "$CONFIG_FILE" ]; then
    enable_sriov=$(grep '^enable_sriov=' "$CONFIG_FILE" | cut -d '=' -f2 | tr -d '"' | tr -d "'" | tr '[:upper:]' '[:lower:]')
    if [ "$enable_sriov" = "true" ]; then
        echo "SR-IOV enabled in config — setting up virtual functions..."
        SRIOV_SCRIPT="${INSTALL_SCRIPTS}/container_setup_sriov.sh"
        if [ -x "$SRIOV_SCRIPT" ]; then
            bash "$SRIOV_SCRIPT" || echo "WARNING: SR-IOV setup failed"
        else
            echo "WARNING: SR-IOV script not found at $SRIOV_SCRIPT"
        fi

        # Install oneshot unit so VFs are re-created on every boot
        SRIOV_UNIT_SRC="${INSTALL_SCRIPTS}/intel-sriov-vf.service"
        if [ -f "$SRIOV_UNIT_SRC" ]; then
            install -m 0644 "$SRIOV_UNIT_SRC" /etc/systemd/system/intel-sriov-vf.service
            systemctl daemon-reload
            systemctl enable intel-sriov-vf.service || echo "WARNING: failed to enable intel-sriov-vf.service"
        else
            echo "WARNING: intel-sriov-vf.service not found at $SRIOV_UNIT_SRC"
        fi
    else
        echo "SR-IOV disabled in config — skipping VF setup"
    fi
fi

# ── CDI (Container Device Interface) setup ───────────────────────────────
# Installs systemd service that generates CDI specs for GPU/NPU on boot and
# on device hotplug. Enables: docker run --device intel.com/gpu=card0
CDI_SCRIPTS="${INSTALL_SCRIPTS}/cdi"
if [ -x "${CDI_SCRIPTS}/systemd/install-systemd.sh" ]; then
    echo "Installing CDI spec generator systemd service..."
    bash "${CDI_SCRIPTS}/systemd/install-systemd.sh" || true

    # Configure Docker to use CDI specs
    DAEMON_JSON="/etc/docker/daemon.json"
    if [ -f "$DAEMON_JSON" ] && ! grep -q '"cdi"' "$DAEMON_JSON" 2>/dev/null; then
        cp "$DAEMON_JSON" "${DAEMON_JSON}.bak"
        python3 -c "
import json
with open('$DAEMON_JSON') as f:
    config = json.load(f)
config.setdefault('features', {})['cdi'] = True
config.setdefault('cdi-spec-dirs', [])
if '/etc/cdi' not in config['cdi-spec-dirs']:
    config['cdi-spec-dirs'].append('/etc/cdi')
with open('$DAEMON_JSON', 'w') as f:
    json.dump(config, f, indent=2)
" 2>/dev/null || echo "WARNING: Could not configure Docker for CDI (python3 unavailable)"
        systemctl restart docker || true
    fi
else
    echo "WARNING: CDI systemd install script not found at ${CDI_SCRIPTS}/systemd/install-systemd.sh"
fi
