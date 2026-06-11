#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# kubernetes-provision.sh — First-boot provisioning for host_type=kubernetes
#
# Called by cloud-init installer.cfg runcmd on the TARGET node after first boot.
# This script expects k3s and docker to already be installed (either via
# auto-install-pkgs.yaml for ISO builds or as packages in ICT images).
#
# Responsibilities:
#   - Disable docker, enable k3s
#   - Wait for k3s API readiness
#   - Copy kubeconfig to edge user
#   - Install Helm (local resources or internet fallback)
#   - Deploy Intel NFD + GPU/NPU device plugins
#   - Configure SR-IOV virtual functions

set -x

LOG_FILE="/var/log/edge-installer.log"
exec >> "$LOG_FILE" 2>&1

date
echo "=== kubernetes-provision.sh: start ==="

# Source proxy and environment variables
. /etc/environment 2>/dev/null || true
# Export so child processes (curl, helm, kubectl, etc.) inherit them
export http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY 2>/dev/null || true

K3S_KUBECONFIG=/etc/rancher/k3s/k3s.yaml
k() { KUBECONFIG="$K3S_KUBECONFIG" kubectl "$@"; }

# ── Disable docker — kubernetes node does not run docker ──────────────────
systemctl disable docker 2>/dev/null || true
systemctl stop docker 2>/dev/null || true

# ── Enable and start k3s ──────────────────────────────────────────────────
# Option 1 (ISO): k3s installed by auto-install-pkgs.yaml; may already be enabled.
# Option 2 (ICT): k3s pre-installed as package; needs to be enabled.
systemctl enable --now k3s

# ── Configure k3s proxy for containerd (if proxy variables are set) ───────
if [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
    echo "Configuring k3s proxy settings..."
    mkdir -p /etc/systemd/system/k3s.service.d
    cat > /etc/systemd/system/k3s.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=${HTTP_PROXY}"
Environment="HTTPS_PROXY=${HTTPS_PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
Environment="CONTAINERD_HTTP_PROXY=${HTTP_PROXY}"
Environment="CONTAINERD_HTTPS_PROXY=${HTTPS_PROXY}"
Environment="CONTAINERD_NO_PROXY=${NO_PROXY}"
EOF
    systemctl daemon-reload
    systemctl restart k3s
    echo "K3s proxy configuration applied"
fi

# ── Wait for k3s kubeconfig (up to 90s) ──────────────────────────────────
echo "Waiting for k3s kubeconfig..."
for i in $(seq 1 45); do
    [ -f /etc/rancher/k3s/k3s.yaml ] && break
    sleep 2
done

# ── Copy kubeconfig to the edge user's home directory ─────────────────────
EDGE_USER=$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" && $7 !~ /(nologin|false|sync)/ {print $1; exit}' /etc/passwd)
if [ -n "$EDGE_USER" ] && [ -f /etc/rancher/k3s/k3s.yaml ]; then
    mkdir -p "/home/${EDGE_USER}/.kube"
    cp /etc/rancher/k3s/k3s.yaml "/home/${EDGE_USER}/.kube/config"
    chown -R "${EDGE_USER}:${EDGE_USER}" "/home/${EDGE_USER}/.kube"
    chmod 600 "/home/${EDGE_USER}/.kube/config"
    # Set KUBECONFIG in the user's .bashrc so kubectl works without sudo
    grep -qxF 'export KUBECONFIG=$HOME/.kube/config' "/home/${EDGE_USER}/.bashrc" || \
        echo 'export KUBECONFIG=$HOME/.kube/config' >> "/home/${EDGE_USER}/.bashrc"
    echo "Kubeconfig copied for ${EDGE_USER}"
fi

# ── Wait for k3s API to be ready (up to 5 minutes) ───────────────────────
echo "Waiting for K3s API server to be ready..."
for i in $(seq 1 60); do
    k get nodes --no-headers 2>/dev/null | grep -q ' Ready' && break
    sleep 5
done
if ! k get nodes >/dev/null 2>&1; then
    echo "ERROR: K3s API not ready after 5 minutes — aborting plugin setup"
    exit 1
fi
echo "K3s nodes:"
k get nodes

# ── Install Helm if not already present ───────────────────────────────────
INSTALL_SCRIPTS="/opt/edge/scripts"
if ! command -v helm >/dev/null 2>&1; then
    if [ -f "${INSTALL_SCRIPTS}/install-helm.sh" ] && ls "${INSTALL_SCRIPTS}"/helm-*-linux-*.tar.gz >/dev/null 2>&1; then
        echo "Installing Helm from local resources..."
        bash "${INSTALL_SCRIPTS}/install-helm.sh"
    else
        # Local helm tarball not bundled (resources/helm/ not present in hook OS).
        # Attempt internet install only if reachable within 10s; skip otherwise.
        echo "Local Helm resources not found — testing internet connectivity..."
        if curl -fsSL --connect-timeout 10 --max-time 10 \
            https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
            -o /tmp/get-helm-3 2>/dev/null; then
            bash /tmp/get-helm-3 || true
            rm -f /tmp/get-helm-3
        else
            echo "WARNING: Helm internet install skipped (endpoint unreachable)."
            echo "  Install Helm manually after first boot:"
            echo "  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
        fi
    fi
else
    echo "Helm already installed: $(helm version --short 2>/dev/null)"
fi

# ── Install NFD + Intel GPU/NPU device plugins ───────────────────────────
# install-intel-device-plugins.sh requires resources/images/ with pre-pulled
# container tarballs. The hook OS only bundles manifests, so fall back to
# applying manifests directly (k3s pulls images at runtime).
apply_manifests_directly() {
    # Manifests are at /opt/edge/scripts/ (flat layout from hook OS)
    [ -f "${INSTALL_SCRIPTS}/nfd.yaml" ] && k apply -f "${INSTALL_SCRIPTS}/nfd.yaml" && sleep 15 || true
    [ -f "${INSTALL_SCRIPTS}/nfd-node-feature-rules.yaml" ] && k apply -f "${INSTALL_SCRIPTS}/nfd-node-feature-rules.yaml" || true
    [ -f "${INSTALL_SCRIPTS}/gpu-plugin.yaml" ] && k apply -f "${INSTALL_SCRIPTS}/gpu-plugin.yaml" || true
    [ -f "${INSTALL_SCRIPTS}/npu-plugin.yaml" ] && k apply -f "${INSTALL_SCRIPTS}/npu-plugin.yaml" || true
}

if [ -f "${INSTALL_SCRIPTS}/install-intel-device-plugins.sh" ]; then
    echo "Running install-intel-device-plugins.sh..."
    KUBECONFIG="$K3S_KUBECONFIG" bash "${INSTALL_SCRIPTS}/install-intel-device-plugins.sh" || {
        echo "WARNING: install-intel-device-plugins.sh failed (likely missing pre-pulled images) — applying manifests directly"
        apply_manifests_directly
    }
else
    echo "WARNING: install-intel-device-plugins.sh not found — applying manifests directly"
    apply_manifests_directly
fi

echo "=== Pod status after plugin installation ==="
k get pods -A

# ── SR-IOV Configuration (Optional) ───────────────────────────────────────
# Set up SR-IOV virtual functions if enabled in config-file
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

date
echo "=== kubernetes-provision.sh: end ==="
