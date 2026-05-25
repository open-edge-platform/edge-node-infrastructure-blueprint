#!/usr/bin/env bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# ==============================================================================
# download-resources.sh
#
# PURPOSE: Download all binaries and images required for offline K3s, Docker,
#          and Helm installation. Run this script ONCE on a machine WITH internet
#          access, then copy the entire directory to your air-gapped target machine(s).
#
# USAGE:
#   ./download-resources.sh
#
# OVERRIDE VERSIONS (optional):
#   K3S_VERSION=v1.32.3+k3s1 DOCKER_VERSION=27.5.1 HELM_VERSION=v3.17.2 ./download-resources.sh
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="${SCRIPT_DIR}/resources"

# ------------------------------------------------------------------------------
# Version pins — update here to change what gets downloaded
# ------------------------------------------------------------------------------
K3S_VERSION="${K3S_VERSION:-v1.32.3+k3s1}"
DOCKER_VERSION="${DOCKER_VERSION:-27.5.1}"
COMPOSE_VERSION="${COMPOSE_VERSION:-v2.33.1}"
HELM_VERSION="${HELM_VERSION:-v3.17.2}"
INTEL_DEVICE_PLUGINS_VERSION="${INTEL_DEVICE_PLUGINS_VERSION:-v0.35.0}"

# ------------------------------------------------------------------------------
# Architecture detection
# ------------------------------------------------------------------------------
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)  K3S_ARCH="amd64";  DOCKER_ARCH="x86_64";  COMPOSE_ARCH="x86_64";  HELM_ARCH="amd64"  ;;
    aarch64) K3S_ARCH="arm64";  DOCKER_ARCH="aarch64"; COMPOSE_ARCH="aarch64"; HELM_ARCH="arm64" ;;
    armv7l)  K3S_ARCH="arm";    DOCKER_ARCH="armhf";   COMPOSE_ARCH="armv7";   HELM_ARCH="arm"   ;;
    *)
        echo "ERROR: Unsupported architecture: ${ARCH}"
        exit 1
        ;;
esac

# Binary name differs for non-amd64 K3s builds
K3S_BINARY="k3s"
[[ "${K3S_ARCH}" != "amd64" ]] && K3S_BINARY="k3s-${K3S_ARCH}"

# ------------------------------------------------------------------------------
# Helper
# ------------------------------------------------------------------------------
info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }

check_dep() {
    command -v "$1" &>/dev/null || { echo "ERROR: '$1' is required but not found. Install it and retry."; exit 1; }
}

# ------------------------------------------------------------------------------
# Preflight
# ------------------------------------------------------------------------------
check_dep curl
check_dep sha256sum

mkdir -p "${RESOURCES_DIR}/k3s"
mkdir -p "${RESOURCES_DIR}/docker"
mkdir -p "${RESOURCES_DIR}/helm"
mkdir -p "${RESOURCES_DIR}/intel-device-plugins/manifests"
mkdir -p "${RESOURCES_DIR}/intel-device-plugins/images"

echo "======================================================================"
echo "  Downloading offline resources"
echo "  K3s           : ${K3S_VERSION}  (${K3S_ARCH})"
  echo "  Docker        : ${DOCKER_VERSION}  (${DOCKER_ARCH})"
  echo "  Compose       : ${COMPOSE_VERSION}"
  echo "  Helm          : ${HELM_VERSION}  (${HELM_ARCH})"
  echo "  Intel Plugins : ${INTEL_DEVICE_PLUGINS_VERSION}"
  echo "  Target        : ${RESOURCES_DIR}"
echo "======================================================================"
echo ""

# ==============================================================================
# K3s
# ==============================================================================
K3S_BASE_URL="https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}"

info "Downloading K3s binary..."
curl -fL "${K3S_BASE_URL}/${K3S_BINARY}" \
    -o "${RESOURCES_DIR}/k3s/k3s"
chmod +x "${RESOURCES_DIR}/k3s/k3s"
success "k3s binary saved"

info "Downloading K3s airgap images (this may take several minutes)..."
# Try the newer .tar.zst format first; fall back to .tar.gz
if curl -fL "${K3S_BASE_URL}/k3s-airgap-images-${K3S_ARCH}.tar.zst" \
        -o "${RESOURCES_DIR}/k3s/k3s-airgap-images-${K3S_ARCH}.tar.zst" 2>/dev/null; then
    success "k3s-airgap-images-${K3S_ARCH}.tar.zst saved"
else
    warn ".tar.zst not found, falling back to .tar.gz"
    curl -fL "${K3S_BASE_URL}/k3s-airgap-images-${K3S_ARCH}.tar.gz" \
        -o "${RESOURCES_DIR}/k3s/k3s-airgap-images-${K3S_ARCH}.tar.gz"
    success "k3s-airgap-images-${K3S_ARCH}.tar.gz saved"
fi

info "Downloading K3s install script..."
curl -fL "https://get.k3s.io" -o "${RESOURCES_DIR}/k3s/install.sh"
chmod +x "${RESOURCES_DIR}/k3s/install.sh"
success "install.sh saved"

info "Downloading K3s checksums..."
curl -fL "${K3S_BASE_URL}/sha256sum-${K3S_ARCH}.txt" \
    -o "${RESOURCES_DIR}/k3s/sha256sum-${K3S_ARCH}.txt"
success "sha256sum-${K3S_ARCH}.txt saved"

# Store the version so install scripts can report it
echo "${K3S_VERSION}" > "${RESOURCES_DIR}/k3s/VERSION"

echo ""
# ==============================================================================
# Docker
# ==============================================================================
DOCKER_STATIC_URL="https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz"

info "Downloading Docker static binaries..."
curl -fL "${DOCKER_STATIC_URL}" \
    -o "${RESOURCES_DIR}/docker/docker-${DOCKER_VERSION}.tgz"
success "docker-${DOCKER_VERSION}.tgz saved"

info "Downloading Docker Compose plugin (${COMPOSE_VERSION})..."
COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${COMPOSE_ARCH}"
curl -fL "${COMPOSE_URL}" \
    -o "${RESOURCES_DIR}/docker/docker-compose"
chmod +x "${RESOURCES_DIR}/docker/docker-compose"
success "docker-compose saved"

# Store the version
echo "${DOCKER_VERSION}" > "${RESOURCES_DIR}/docker/VERSION"

echo ""
# ==============================================================================
# Helm
# ==============================================================================
HELM_OS="linux"
HELM_TARBALL="helm-${HELM_VERSION}-${HELM_OS}-${HELM_ARCH}.tar.gz"
HELM_BASE_URL="https://get.helm.sh"

info "Downloading Helm ${HELM_VERSION} (${HELM_OS}/${HELM_ARCH})..."
curl -fL "${HELM_BASE_URL}/${HELM_TARBALL}" \
    -o "${RESOURCES_DIR}/helm/${HELM_TARBALL}"
success "${HELM_TARBALL} saved"

info "Downloading Helm checksum..."
curl -fL "${HELM_BASE_URL}/${HELM_TARBALL}.sha256sum" \
    -o "${RESOURCES_DIR}/helm/${HELM_TARBALL}.sha256sum"
success "${HELM_TARBALL}.sha256sum saved"

# Store the version
echo "${HELM_VERSION}" > "${RESOURCES_DIR}/helm/VERSION"

echo ""
# ==============================================================================
# Intel Device Plugins (NFD + GPU + NPU)
# ==============================================================================
# Requires: kubectl (for kustomize manifest rendering) and docker (for image
# pulling/saving).  If either tool is absent, this section is skipped and a
# warning is printed.  Set SKIP_INTEL_PLUGINS=1 to skip intentionally.
#
# OVERRIDE VERSION:
#   INTEL_DEVICE_PLUGINS_VERSION=v0.35.0 ./download-resources.sh
# ==============================================================================

INTEL_DIR="${RESOURCES_DIR}/intel-device-plugins"
INTEL_MANIFESTS_DIR="${INTEL_DIR}/manifests"
INTEL_IMAGES_DIR="${INTEL_DIR}/images"
INTEL_BASE="github.com/intel/intel-device-plugins-for-kubernetes/deployments"

if [[ "${SKIP_INTEL_PLUGINS:-0}" == "1" ]]; then
    warn "Skipping Intel device plugins section (SKIP_INTEL_PLUGINS=1)"
elif ! command -v kubectl &>/dev/null; then
    warn "'kubectl' not found — skipping Intel device plugins manifests."
    warn "Install kubectl and re-run to include Intel device plugin resources."
elif ! command -v docker &>/dev/null; then
    warn "'docker' not found — skipping Intel device plugins images."
    warn "Install Docker and re-run to include Intel device plugin resources."
else
    echo "====================================================================="
    echo "  Downloading Intel Device Plugins ${INTEL_DEVICE_PLUGINS_VERSION}"
    echo "====================================================================="
    echo ""

    # --------------------------------------------------------------------------
    # Render Kustomize overlays to static YAML
    #
    # kubectl kustomize fetches manifests directly from the GitHub repository
    # (needs internet on this download machine) and writes fully resolved YAML.
    # The resulting files are applied offline on the target machine.
    # --------------------------------------------------------------------------
    declare -A OVERLAYS=(
        ["nfd"]="${INTEL_BASE}/nfd?ref=${INTEL_DEVICE_PLUGINS_VERSION}"
        ["nfd-node-feature-rules"]="${INTEL_BASE}/nfd/overlays/node-feature-rules?ref=${INTEL_DEVICE_PLUGINS_VERSION}"
        ["gpu-plugin"]="${INTEL_BASE}/gpu_plugin/overlays/nfd_labeled_nodes?ref=${INTEL_DEVICE_PLUGINS_VERSION}"
        ["npu-plugin"]="${INTEL_BASE}/npu_plugin/overlays/nfd_labeled_nodes?ref=${INTEL_DEVICE_PLUGINS_VERSION}"
    )

    for name in nfd nfd-node-feature-rules gpu-plugin npu-plugin; do
        info "Rendering manifest: ${name}.yaml ..."
        kubectl kustomize "${OVERLAYS[${name}]}" \
            > "${INTEL_MANIFESTS_DIR}/${name}.yaml"
        success "Saved: intel-device-plugins/manifests/${name}.yaml"
    done

    echo ""

    # --------------------------------------------------------------------------
    # Extract unique container images from all rendered manifests
    # --------------------------------------------------------------------------
    info "Extracting container image references from manifests ..."
    INTEL_IMAGES=$(grep -h '^[[:space:]]*image:' "${INTEL_MANIFESTS_DIR}"/*.yaml \
        | sed -E 's/[[:space:]]*image:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/' \
        | sort -u)

    if [[ -z "${INTEL_IMAGES}" ]]; then
        warn "No image references found in rendered manifests."
    fi

    # --------------------------------------------------------------------------
    # Pull and save each image as a tar archive
    #
    # Archives are imported on the target machine via 'k3s ctr images import',
    # which loads them directly into k3s's private containerd storage.
    # --------------------------------------------------------------------------
    for image in ${INTEL_IMAGES}; do
        # Derive a filesystem-safe filename from the image reference
        safe_name="$(echo "${image}" | tr '/.:' '---')"
        info "Pulling: ${image} ..."
        docker pull "${image}"
        docker save "${image}" -o "${INTEL_IMAGES_DIR}/${safe_name}.tar"
        success "Saved image: intel-device-plugins/images/${safe_name}.tar"
    done

    # Store the version for the install script to report
    echo "${INTEL_DEVICE_PLUGINS_VERSION}" > "${INTEL_DIR}/VERSION"

    echo ""
    success "Intel device plugins resources saved to ${INTEL_DIR}/"
fi

# ==============================================================================
# Intel CDI GPU Spec Generator (build from source)
# ==============================================================================
# Requires: Go 1.22+ and git.  Set SKIP_CDI_BUILD=1 to skip.
# ==============================================================================

CDI_DIR="${SCRIPT_DIR}/cdi"
CDI_GPU_GENERATOR="${CDI_DIR}/intel-cdi-specs-generator-gpu"

if [[ "${SKIP_CDI_BUILD:-0}" == "1" ]]; then
    warn "Skipping CDI GPU generator build (SKIP_CDI_BUILD=1)"
elif [[ -x "$CDI_GPU_GENERATOR" ]]; then
    info "CDI GPU generator already built: ${CDI_GPU_GENERATOR}"
elif ! command -v go &>/dev/null; then
    warn "'go' not found — skipping CDI GPU generator build. Install Go 1.22+ and re-run."
else
    info "Building intel-cdi-specs-generator-gpu from source..."
    if bash "${CDI_DIR}/build-gpu-generator.sh"; then
        success "CDI GPU generator built: ${CDI_GPU_GENERATOR} ($(du -h "$CDI_GPU_GENERATOR" | cut -f1))"
    else
        warn "CDI GPU generator build failed. Run manually: ${CDI_DIR}/build-gpu-generator.sh"
    fi
fi

echo ""

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "======================================================================"
echo "  Download complete!"
echo "======================================================================"
echo ""
echo "K3s resources:"
ls -lh "${RESOURCES_DIR}/k3s/"
echo ""
echo "Docker resources:"
ls -lh "${RESOURCES_DIR}/docker/"
echo ""
echo "Helm resources:"
ls -lh "${RESOURCES_DIR}/helm/"
echo ""
if [[ -d "${RESOURCES_DIR}/intel-device-plugins/manifests" ]]; then
    echo "Intel device plugin resources:"
    ls -lh "${RESOURCES_DIR}/intel-device-plugins/manifests/"
    echo ""
    ls -lh "${RESOURCES_DIR}/intel-device-plugins/images/"
    echo ""
fi
if [[ -x "${CDI_DIR}/intel-cdi-specs-generator-gpu" ]]; then
    echo "CDI resources:"
    ls -lh "${CDI_DIR}/intel-cdi-specs-generator-gpu"
    echo ""
fi
echo "Next steps:"
echo "  1. Copy this entire directory to the target (air-gapped) machine(s)."
echo "  2. On the target machine, run as root (or with sudo):"
echo "       sudo ./install-docker.sh"
echo "       sudo ./install-k3s.sh"
echo "       sudo ./install-helm.sh"
echo "       sudo ./install-intel-device-plugins.sh"
echo ""
echo "  For container mode (host_type=container), CDI is set up automatically"
echo "  during first-boot provisioning via container-provision.sh."
echo ""
