#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# ==============================================================================
# install-intel-device-plugins.sh
#
# PURPOSE: Install Intel Node Feature Discovery (NFD) and Intel GPU/NPU device
#          plugins on a K3s cluster in fully air-gapped mode.
#
#          Uses pre-rendered manifests and pre-pulled container images from the
#          resources/intel-device-plugins/ directory populated by
#          download-resources.sh.  No internet access is required at install time.
#
# PREREQUISITES:
#   - K3s must be installed and running       (install-k3s.sh)
#   - resources/intel-device-plugins/ must exist (download-resources.sh)
#
# USAGE:
#   sudo ./install-intel-device-plugins.sh
#
# OPTIONAL ENV VARS:
#   INTEL_PLUGINS_NS   namespace for GPU/NPU device plugins  (default: intel-device-plugins)
#   NFD_NS             namespace for NFD                     (default: node-feature-discovery)
#   SKIP_GPU           set to "1" to skip the GPU plugin     (default: 0)
#   SKIP_NPU           set to "1" to skip the NPU plugin     (default: 0)
#   NFD_READY_TIMEOUT  seconds to wait for NFD pods          (default: 180)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="${SCRIPT_DIR}/resources/intel-device-plugins"

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
INTEL_PLUGINS_NS="${INTEL_PLUGINS_NS:-intel-device-plugins}"
NFD_NS="${NFD_NS:-node-feature-discovery}"
SKIP_GPU="${SKIP_GPU:-0}"
SKIP_NPU="${SKIP_NPU:-0}"
NFD_READY_TIMEOUT="${NFD_READY_TIMEOUT:-180}"

# K3s installs its kubeconfig at /etc/rancher/k3s/k3s.yaml; set it if not
# already configured so kubectl works under sudo.
if [[ -z "${KUBECONFIG:-}" && -f /etc/rancher/k3s/k3s.yaml ]]; then
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
fi

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }
die()     { echo "[ERROR] $*" >&2; exit 1; }

# Wait for all pods in a namespace to reach Ready state.
# Usage: wait_pods_ready <namespace> <timeout_seconds>
wait_pods_ready() {
    local ns="$1"
    local timeout="$2"

    info "Waiting for pods in '${ns}' to be created ..."
    local elapsed=0
    while [[ "${elapsed}" -lt 60 ]]; do
        local count
        count=$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null | wc -l || echo "0")
        [[ "${count}" -gt 0 ]] && break
        sleep 3
        elapsed=$((elapsed + 3))
    done

    info "Waiting for pods in '${ns}' to be ready (timeout: ${timeout}s) ..."
    kubectl wait pod --all \
        -n "${ns}" \
        --for=condition=ready \
        --timeout="${timeout}s" \
        || warn "Some pods in '${ns}' did not become ready within ${timeout}s. Check: kubectl get pods -n ${ns}"
}

# Apply a manifest, optionally scoped to a namespace.
# Usage: kube_apply <manifest_path> [namespace]
kube_apply() {
    local manifest="$1"
    local ns="${2:-}"
    [[ -f "${manifest}" ]] || die "Manifest not found: ${manifest}"
    if [[ -n "${ns}" ]]; then
        kubectl apply -n "${ns}" -f "${manifest}"
    else
        kubectl apply -f "${manifest}"
    fi
}

# ------------------------------------------------------------------------------
# Preflight checks
# ------------------------------------------------------------------------------
[[ "${EUID}" -ne 0 ]] && die "This script must be run as root.  Use: sudo $0"

[[ -d "${RESOURCES_DIR}" ]] || \
    die "Resources directory not found: ${RESOURCES_DIR}\nRun './download-resources.sh' first."
[[ -d "${RESOURCES_DIR}/manifests" ]] || \
    die "Manifests directory not found: ${RESOURCES_DIR}/manifests\nRun './download-resources.sh' first."
[[ -d "${RESOURCES_DIR}/images" ]] || \
    die "Images directory not found: ${RESOURCES_DIR}/images\nRun './download-resources.sh' first."

command -v kubectl &>/dev/null || \
    die "'kubectl' not found. Ensure K3s is installed and /usr/local/bin is in PATH."
command -v k3s &>/dev/null || \
    die "'k3s' not found. Ensure K3s is installed."

kubectl get nodes &>/dev/null || \
    die "Cannot reach the Kubernetes API. Ensure k3s is running: sudo systemctl status k3s"

VERSION="$(cat "${RESOURCES_DIR}/VERSION" 2>/dev/null || echo "unknown")"

echo "======================================================================"
echo "  Installing Intel Device Plugins (air-gapped)"
echo "  Version    : ${VERSION}"
echo "  Plugins NS : ${INTEL_PLUGINS_NS}"
echo "  NFD NS     : ${NFD_NS}"
echo "  GPU plugin : $([[ "${SKIP_GPU}" == "1" ]] && echo "skip" || echo "enabled")"
echo "  NPU plugin : $([[ "${SKIP_NPU}" == "1" ]] && echo "skip" || echo "enabled")"
echo "======================================================================"
echo ""

# ==============================================================================
# Step 1 — Import container images into k3s containerd
#
# k3s uses its own containerd instance. Images must be imported via
# 'k3s ctr images import' rather than loaded through Docker.
# ==============================================================================
info "Importing container images into k3s containerd ..."
echo ""

IMAGE_COUNT=0
shopt -s nullglob
for tar_file in "${RESOURCES_DIR}/images/"*.tar; do
    info "  Importing: $(basename "${tar_file}") ..."
    k3s ctr images import "${tar_file}"
    IMAGE_COUNT=$((IMAGE_COUNT + 1))
done
shopt -u nullglob

if [[ "${IMAGE_COUNT}" -eq 0 ]]; then
    warn "No image archives found in ${RESOURCES_DIR}/images/."
    warn "Pods may fail to start if images cannot be pulled from the internet."
else
    success "Imported ${IMAGE_COUNT} image archive(s)"
fi
echo ""

# ==============================================================================
# Step 2 — Create namespaces
#
# intel-device-plugins  : holds the GPU and NPU device plugin DaemonSets.
# node-feature-discovery: holds the NFD master Deployment and worker DaemonSet.
# ==============================================================================
info "Creating namespace: ${INTEL_PLUGINS_NS} ..."
kubectl create namespace "${INTEL_PLUGINS_NS}" --dry-run=client -o yaml | kubectl apply -f -

info "Creating namespace: ${NFD_NS} ..."
kubectl create namespace "${NFD_NS}" --dry-run=client -o yaml | kubectl apply -f -

success "Namespaces ready"
echo ""

# ==============================================================================
# Step 3 — Label namespaces for Pod Security Admission
#
# The device plugins and NFD need privileged access to host device files,
# hostPath mounts, and kernel modules, so the namespaces must be granted the
# privileged Pod Security Standard.
# ==============================================================================
info "Applying Pod Security Admission labels ..."
for ns in "${INTEL_PLUGINS_NS}" "${NFD_NS}"; do
    kubectl label namespace "${ns}" \
        pod-security.kubernetes.io/enforce=privileged \
        pod-security.kubernetes.io/audit=privileged \
        pod-security.kubernetes.io/warn=privileged \
        --overwrite
    success "  ${ns} — PSA labels set"
done
echo ""

# ==============================================================================
# Step 4 — Install Node Feature Discovery (NFD)
#
# NFD must run BEFORE the Intel NodeFeatureRules and device plugins, so that
# by the time the plugins look for node labels the labels already exist.
# ==============================================================================
info "Applying NFD manifest ..."
kube_apply "${RESOURCES_DIR}/manifests/nfd.yaml"
success "NFD manifest applied"
echo ""

wait_pods_ready "${NFD_NS}" "${NFD_READY_TIMEOUT}"
success "NFD is running"
echo ""

# ==============================================================================
# Step 5 — Apply Intel GPU/NPU NodeFeatureRules
#
# These custom resource instances tell NFD which hardware features to detect
# and which labels to apply to nodes.
# ==============================================================================
info "Applying Intel NodeFeatureRules ..."
kube_apply "${RESOURCES_DIR}/manifests/nfd-node-feature-rules.yaml"
success "NodeFeatureRules applied"
echo ""

# Give NFD worker pods a moment to run the new rules and label the node before
# the device plugins start inspecting node labels.
info "Pausing 15s for NFD workers to process NodeFeatureRules ..."
sleep 15
echo ""

# ==============================================================================
# Step 6 — Install Intel GPU device plugin
#
# The overlay targets only nodes labelled by NFD, so on nodes without Intel
# GPU hardware the DaemonSet will simply not schedule any pods.
# ==============================================================================
if [[ "${SKIP_GPU}" != "1" ]]; then
    info "Applying Intel GPU device plugin ..."
    kube_apply "${RESOURCES_DIR}/manifests/gpu-plugin.yaml" "${INTEL_PLUGINS_NS}"
    success "GPU device plugin applied"
    echo ""
else
    warn "Skipping GPU plugin (SKIP_GPU=1)"
    echo ""
fi

# ==============================================================================
# Step 7 — Install Intel NPU device plugin
#
# Same approach as the GPU plugin — only schedules on NFD-labelled nodes.
# ==============================================================================
if [[ "${SKIP_NPU}" != "1" ]]; then
    info "Applying Intel NPU device plugin ..."
    kube_apply "${RESOURCES_DIR}/manifests/npu-plugin.yaml" "${INTEL_PLUGINS_NS}"
    success "NPU device plugin applied"
    echo ""
else
    warn "Skipping NPU plugin (SKIP_NPU=1)"
    echo ""
fi

# ==============================================================================
# Summary
# ==============================================================================
echo "======================================================================"
echo "  Intel Device Plugins installation complete!"
echo "======================================================================"
echo ""
echo "  Check NFD pods:"
echo "    kubectl get pods -n ${NFD_NS}"
echo ""
echo "  Check device plugin pods:"
echo "    kubectl get pods -n ${INTEL_PLUGINS_NS}"
echo ""
echo "  Verify Intel node labels:"
echo "    kubectl get nodes --show-labels | tr ',' '\\n' | grep intel"
echo ""
echo "  Verify GPU labels:"
echo "    kubectl get nodes --show-labels | tr ',' '\\n' | grep 'gpu.intel.com'"
echo ""
echo "  Verify NPU labels:"
echo "    kubectl get nodes --show-labels | tr ',' '\\n' | grep 'npu.intel.com\\|intel.feature.node.kubernetes.io/npu'"
echo ""
