#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# ==============================================================================
# install-helm.sh
#
# PURPOSE: Install Helm from a locally stored tarball (air-gapped / offline).
#          No internet access is required.  The tarball must have been downloaded
#          by download-resources.sh beforehand.
#
# USAGE:
#   sudo ./install-helm.sh
#
# OPTIONAL ENV VARS:
#   HELM_INSTALL_DIR   installation directory for the helm binary  (default: /usr/local/bin)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="${SCRIPT_DIR}/resources/helm"

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
HELM_INSTALL_DIR="${HELM_INSTALL_DIR:-/usr/local/bin}"

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

[[ -d "${RESOURCES_DIR}" ]] || die "Resources directory not found: ${RESOURCES_DIR}\nRun './download-resources.sh' on a machine with internet access first."

command -v sha256sum &>/dev/null || die "'sha256sum' is required but was not found."

# Architecture
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)  HELM_ARCH="amd64" ;;
    aarch64) HELM_ARCH="arm64" ;;
    armv7l)  HELM_ARCH="arm"   ;;
    *) die "Unsupported architecture: ${ARCH}" ;;
esac

# Locate the tarball
HELM_TARBALL=""
while IFS= read -r f; do
    HELM_TARBALL="${f}"
    break
done < <(find "${RESOURCES_DIR}" -maxdepth 1 -name "helm-*-linux-${HELM_ARCH}.tar.gz" | sort -V)

[[ -n "${HELM_TARBALL}" ]] || die "Helm tarball (helm-*-linux-${HELM_ARCH}.tar.gz) not found in ${RESOURCES_DIR}.\nRun './download-resources.sh' first."

VERSION="$(cat "${RESOURCES_DIR}/VERSION" 2>/dev/null || basename "${HELM_TARBALL}" | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+')"

echo "======================================================================"
echo "  Installing Helm (air-gapped)"
echo "  Version  : ${VERSION}"
echo "  Package  : $(basename "${HELM_TARBALL}")"
echo "  Dest     : ${HELM_INSTALL_DIR}"
echo "======================================================================"
echo ""

# ==============================================================================
# 1. Verify checksum (if available)
# ==============================================================================
CHECKSUM_FILE="${HELM_TARBALL}.sha256sum"
if [[ -f "${CHECKSUM_FILE}" ]]; then
    info "Verifying checksum ..."
    # sha256sum file contains an absolute path; rebuild it relative to RESOURCES_DIR
    EXPECTED_SUM="$(awk '{print $1}' "${CHECKSUM_FILE}")"
    ACTUAL_SUM="$(sha256sum "${HELM_TARBALL}" | awk '{print $1}')"
    if [[ "${EXPECTED_SUM}" != "${ACTUAL_SUM}" ]]; then
        die "Checksum mismatch for $(basename "${HELM_TARBALL}")!\n  Expected: ${EXPECTED_SUM}\n  Got     : ${ACTUAL_SUM}\nDelete the file and re-run download-resources.sh."
    fi
    success "Checksum verified"
else
    echo "[WARN]  No checksum file found — skipping verification."
fi

# ==============================================================================
# 2. Extract Helm binary
# ==============================================================================
info "Extracting $(basename "${HELM_TARBALL}") ..."

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

tar -xzf "${HELM_TARBALL}" -C "${TMPDIR}"

# The tarball unpacks as linux-<arch>/helm
HELM_BIN="$(find "${TMPDIR}" -maxdepth 2 -name "helm" -type f | head -n1)"
[[ -n "${HELM_BIN}" ]] || die "helm binary not found inside the tarball."

# ==============================================================================
# 3. Install
# ==============================================================================
info "Installing helm → ${HELM_INSTALL_DIR}/helm ..."
install -m 0755 "${HELM_BIN}" "${HELM_INSTALL_DIR}/helm"
success "helm installed"

# ==============================================================================
# 4. Verify
# ==============================================================================
echo ""
echo "======================================================================"
echo "  Helm installation complete!"
echo "======================================================================"
echo ""
echo "  Installed version:"
helm version
echo ""
echo "  Quick-start (offline chart usage):"
echo "    # Add a chart repo from a local path:"
echo "    helm repo add local file:///path/to/charts"
echo ""
echo "    # Install a chart from a local .tgz package:"
echo "    helm install my-release /path/to/chart-x.y.z.tgz"
echo ""
echo "    # Install a chart into a specific namespace:"
echo "    helm install my-release /path/to/chart-x.y.z.tgz -n my-namespace --create-namespace"
echo ""
echo "  Auto-complete (bash):"
echo "    helm completion bash > /etc/bash_completion.d/helm"
echo ""
