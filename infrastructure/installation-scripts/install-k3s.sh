#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# ==============================================================================
# install-k3s.sh
#
# PURPOSE: Install K3s in fully air-gapped mode using resources pre-downloaded
#          by download-resources.sh.  No internet access is required.
#
# USAGE — server (control-plane):
#   sudo ./install-k3s.sh
#
# USAGE — agent (worker node):
#   sudo K3S_MODE=agent K3S_URL=https://<server-ip>:6443 K3S_TOKEN=<token> \
#       ./install-k3s.sh
#
# OPTIONAL ENV VARS:
#   K3S_MODE          server | agent           (default: server)
#   K3S_URL           https://<ip>:6443        (required for agent mode)
#   K3S_TOKEN         <cluster token>          (required for agent mode)
#   K3S_CONFIG_FILE   path to k3s config yaml  (optional)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="${SCRIPT_DIR}/resources/k3s"

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
K3S_MODE="${K3S_MODE:-server}"
K3S_URL="${K3S_URL:-}"
K3S_TOKEN="${K3S_TOKEN:-}"
K3S_INSTALL_DIR="/usr/local/bin"
K3S_IMAGES_DIR="/var/lib/rancher/k3s/agent/images"
K3S_CONFIG_DIR="/etc/rancher/k3s"

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
die()     { echo "[ERROR] $*" >&2; exit 1; }

# ------------------------------------------------------------------------------
# Preflight checks
# ------------------------------------------------------------------------------
[[ "${EUID}" -ne 0 ]] && die "This script must be run as root.  Use: sudo $0"

[[ -d "${RESOURCES_DIR}" ]]        || die "Resources directory not found: ${RESOURCES_DIR}\nRun './download-resources.sh' on a machine with internet access first."
[[ -f "${RESOURCES_DIR}/k3s" ]]    || die "K3s binary not found in ${RESOURCES_DIR}.\nRun './download-resources.sh' first."
[[ -f "${RESOURCES_DIR}/install.sh" ]] || die "K3s install script not found in ${RESOURCES_DIR}.\nRun './download-resources.sh' first."

# Architecture
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)  K3S_ARCH="amd64" ;;
    aarch64) K3S_ARCH="arm64" ;;
    armv7l)  K3S_ARCH="arm"   ;;
    *) die "Unsupported architecture: ${ARCH}" ;;
esac

# Agent-mode requires URL + token
if [[ "${K3S_MODE}" == "agent" ]]; then
    [[ -n "${K3S_URL}" ]]   || die "K3S_URL must be set for agent mode.\n  Example: K3S_URL=https://<server-ip>:6443"
    [[ -n "${K3S_TOKEN}" ]] || die "K3S_TOKEN must be set for agent mode.\n  Retrieve it from the server: sudo cat /var/lib/rancher/k3s/server/node-token"
fi

VERSION="$(cat "${RESOURCES_DIR}/VERSION" 2>/dev/null || echo "unknown")"

echo "======================================================================"
echo "  Installing K3s (air-gapped)"
echo "  Version : ${VERSION}"
echo "  Mode    : ${K3S_MODE}"
echo "  Arch    : ${K3S_ARCH}"
echo "======================================================================"
echo ""

# ==============================================================================
# 1. Install the K3s binary
# ==============================================================================
info "Installing K3s binary to ${K3S_INSTALL_DIR}/k3s ..."
install -m 0755 "${RESOURCES_DIR}/k3s" "${K3S_INSTALL_DIR}/k3s"
success "K3s binary installed"

# ==============================================================================
# 2. Stage airgap images
#    K3s reads pre-loaded images from /var/lib/rancher/k3s/agent/images/ on boot.
# ==============================================================================
info "Staging airgap image archive ..."
mkdir -p "${K3S_IMAGES_DIR}"

STAGED=0
for ext in tar.zst tar.gz; do
    src="${RESOURCES_DIR}/k3s-airgap-images-${K3S_ARCH}.${ext}"
    if [[ -f "${src}" ]]; then
        cp -f "${src}" "${K3S_IMAGES_DIR}/"
        success "Staged $(basename "${src}") → ${K3S_IMAGES_DIR}/"
        STAGED=1
        break
    fi
done

if [[ "${STAGED}" -eq 0 ]]; then
    echo "[WARN]  No airgap image archive found in ${RESOURCES_DIR}."
    echo "        K3s will try to pull images from the internet."
    echo "        Re-run download-resources.sh to include the image archive."
fi

# ==============================================================================
# 3. Ensure config directory exists (root-only)
# ==============================================================================
install -d -m 0700 -o root -g root "${K3S_CONFIG_DIR}"

# Copy a user-supplied config if provided. Permissions hardened to 0600 root:root
# because the config may contain `token:` or other secrets.
if [[ -n "${K3S_CONFIG_FILE:-}" && -f "${K3S_CONFIG_FILE}" ]]; then
    info "Copying config file ${K3S_CONFIG_FILE} → ${K3S_CONFIG_DIR}/config.yaml"
    install -m 0600 -o root -g root "${K3S_CONFIG_FILE}" "${K3S_CONFIG_DIR}/config.yaml"
fi

# Persist server URL and join token to a permission-hardened drop-in.
if [[ "${K3S_MODE}" == "agent" ]]; then
    install -d -m 0700 -o root -g root "${K3S_CONFIG_DIR}/config.yaml.d"
    AGENT_DROPIN="${K3S_CONFIG_DIR}/config.yaml.d/00-agent.yaml"
    ( umask 077 && cat > "${AGENT_DROPIN}" <<EOF
server: ${K3S_URL}
token: ${K3S_TOKEN}
EOF
    )
    chmod 0600 "${AGENT_DROPIN}"
    chown root:root "${AGENT_DROPIN}"
    # Drop the token from this script's env
    unset K3S_TOKEN
fi

# ==============================================================================
# 4. Run the K3s install script in air-gapped mode
#    INSTALL_K3S_SKIP_DOWNLOAD=true tells the script to use the binary already
#    present in INSTALL_K3S_BIN_DIR instead of fetching it from the internet.
# ==============================================================================
info "Running K3s installer (offline mode) ..."
echo ""

INSTALL_ARGS=()
[[ "${K3S_MODE}" == "agent" ]] && INSTALL_ARGS+=(agent)

INSTALL_K3S_SKIP_DOWNLOAD=true \
INSTALL_K3S_BIN_DIR="${K3S_INSTALL_DIR}" \
bash "${RESOURCES_DIR}/install.sh" "${INSTALL_ARGS[@]}"

# ==============================================================================
# 5. Post-install guidance
# ==============================================================================
echo ""
echo "======================================================================"
echo "  K3s installation complete!"
echo "======================================================================"
echo ""

if [[ "${K3S_MODE}" == "server" ]]; then
    echo "  Check service status:"
    echo "    sudo systemctl status k3s"
    echo ""
    echo "  View nodes:"
    echo "    sudo kubectl get nodes"
    echo ""
    echo "  Use kubectl as non-root:"
    echo "    mkdir -p ~/.kube"
    echo "    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config"
    echo "    sudo chown \$(id -u):\$(id -g) ~/.kube/config"
    echo ""
    echo "  Retrieve the join token for worker nodes:"
    echo "    sudo cat /var/lib/rancher/k3s/server/node-token"
    echo ""
    echo "  Join a worker node:"
    echo "    sudo K3S_MODE=agent K3S_URL=https://$(hostname -I | awk '{print $1}'):6443 \\"
    echo "         K3S_TOKEN=<token> ./install-k3s.sh"
else
    echo "  Check service status:"
    echo "    sudo systemctl status k3s-agent"
fi
echo ""
