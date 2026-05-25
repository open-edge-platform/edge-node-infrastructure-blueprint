#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# ==============================================================================
# install-docker.sh
#
# PURPOSE: Install Docker Engine from a locally stored static binary tarball.
#          No internet access is required.  The tarball must have been downloaded
#          by download-resources.sh beforehand.
#
#          Uses Docker's official static builds — works on any x86_64/aarch64
#          Linux distribution (distro-agnostic, no package manager needed).
#
# USAGE:
#   sudo ./install-docker.sh
#
# OPTIONAL ENV VARS:
#   DOCKER_INSTALL_DIR   installation directory for binaries  (default: /usr/local/bin)
#   SKIP_SERVICE_START   set to "1" to install without starting the service
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="${SCRIPT_DIR}/resources/docker"

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
DOCKER_INSTALL_DIR="${DOCKER_INSTALL_DIR:-/usr/local/bin}"
DOCKER_DATA_DIR="/var/lib/docker"
DOCKER_CONFIG_DIR="/etc/docker"
COMPOSE_PLUGIN_DIR="/usr/local/lib/docker/cli-plugins"
SKIP_SERVICE_START="${SKIP_SERVICE_START:-0}"

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }
die()     { echo "[ERROR] $*" >&2; exit 1; }

# ------------------------------------------------------------------------------
# Preflight checks
# ------------------------------------------------------------------------------
[[ "${EUID}" -ne 0 ]] && die "This script must be run as root.  Use: sudo $0"

[[ -d "${RESOURCES_DIR}" ]] || die "Resources directory not found: ${RESOURCES_DIR}\nRun './download-resources.sh' on a machine with internet access first."

command -v systemctl &>/dev/null || die "systemd is required but 'systemctl' was not found."

# Locate the tarball
DOCKER_TARBALL=""
while IFS= read -r f; do
    DOCKER_TARBALL="${f}"
    break
done < <(find "${RESOURCES_DIR}" -maxdepth 1 -name "docker-*.tgz" | sort -V)

[[ -n "${DOCKER_TARBALL}" ]] || die "Docker tarball (docker-*.tgz) not found in ${RESOURCES_DIR}.\nRun './download-resources.sh' first."

VERSION="$(cat "${RESOURCES_DIR}/VERSION" 2>/dev/null || basename "${DOCKER_TARBALL}" .tgz | sed 's/docker-//')"

echo "======================================================================"
echo "  Installing Docker Engine (offline, static binary)"
echo "  Version  : ${VERSION}"
echo "  Package  : $(basename "${DOCKER_TARBALL}")"
echo "  Dest     : ${DOCKER_INSTALL_DIR}"
echo "======================================================================"
echo ""

# ==============================================================================
# 1. Extract and install Docker binaries
# ==============================================================================
info "Extracting Docker binaries from $(basename "${DOCKER_TARBALL}") ..."

TMPDIR="$(mktemp -d)"
# Ensure temp dir is cleaned up on exit/error
trap 'rm -rf "${TMPDIR}"' EXIT

tar -xzf "${DOCKER_TARBALL}" -C "${TMPDIR}"
EXTRACTED="${TMPDIR}/docker"

[[ -d "${EXTRACTED}" ]] || die "Unexpected tarball layout — expected a 'docker/' subdirectory inside the archive."

info "Installing binaries to ${DOCKER_INSTALL_DIR} ..."

# Core Docker binaries
for bin in docker dockerd docker-init docker-proxy; do
    if [[ -f "${EXTRACTED}/${bin}" ]]; then
        install -m 0755 "${EXTRACTED}/${bin}" "${DOCKER_INSTALL_DIR}/${bin}"
        success "  ${bin}"
    fi
done

# containerd + shims
for bin in containerd containerd-shim containerd-shim-runc-v2 ctr; do
    if [[ -f "${EXTRACTED}/${bin}" ]]; then
        install -m 0755 "${EXTRACTED}/${bin}" "${DOCKER_INSTALL_DIR}/${bin}"
        success "  ${bin}"
    fi
done

# runc
if [[ -f "${EXTRACTED}/runc" ]]; then
    install -m 0755 "${EXTRACTED}/runc" "${DOCKER_INSTALL_DIR}/runc"
    success "  runc"
fi

# ==============================================================================
# 2. Install Docker Compose plugin (optional)
# ==============================================================================
if [[ -f "${RESOURCES_DIR}/docker-compose" ]]; then
    info "Installing Docker Compose plugin ..."
    mkdir -p "${COMPOSE_PLUGIN_DIR}"
    install -m 0755 "${RESOURCES_DIR}/docker-compose" "${COMPOSE_PLUGIN_DIR}/docker-compose"
    # Symlink so it is also accessible as a standalone command
    ln -sf "${COMPOSE_PLUGIN_DIR}/docker-compose" "${DOCKER_INSTALL_DIR}/docker-compose"
    success "Docker Compose plugin installed (docker compose)"
else
    warn "docker-compose not found in ${RESOURCES_DIR} — skipping Compose installation."
fi

# ==============================================================================
# 3. Create docker group and directories
# ==============================================================================
if ! getent group docker &>/dev/null; then
    info "Creating 'docker' group ..."
    groupadd --system docker
    success "docker group created"
fi

mkdir -p "${DOCKER_DATA_DIR}" "${DOCKER_CONFIG_DIR}"

# ==============================================================================
# 4. Write default daemon.json (only if not already present)
# ==============================================================================
if [[ ! -f "${DOCKER_CONFIG_DIR}/daemon.json" ]]; then
    info "Writing default daemon config → ${DOCKER_CONFIG_DIR}/daemon.json ..."
    cat > "${DOCKER_CONFIG_DIR}/daemon.json" <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    success "daemon.json written"
fi

# ==============================================================================
# 5. Install systemd unit files
# ==============================================================================
info "Installing containerd systemd service ..."
cat > /etc/systemd/system/containerd.service <<'EOF'
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=1048576
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF
success "containerd.service written"

info "Installing docker.socket systemd unit ..."
cat > /etc/systemd/system/docker.socket <<'EOF'
[Unit]
Description=Docker Socket for the API

[Socket]
ListenStream=/var/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF
success "docker.socket written"

info "Installing docker.service systemd unit ..."
cat > /etc/systemd/system/docker.service <<'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service containerd.service
Wants=network-online.target
Requires=docker.socket containerd.service

[Service]
Type=notify
ExecStart=/usr/local/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF
success "docker.service written"

# ==============================================================================
# 6. Enable and (optionally) start services
# ==============================================================================
info "Reloading systemd daemon ..."
systemctl daemon-reload

info "Enabling services to start on boot ..."
systemctl enable containerd
systemctl enable docker.socket
systemctl enable docker
success "Services enabled"

if [[ "${SKIP_SERVICE_START}" != "1" ]]; then
    info "Starting containerd ..."
    systemctl start containerd

    info "Starting docker.socket ..."
    systemctl start docker.socket

    info "Starting docker ..."
    systemctl start docker
    success "Services started"
fi

# ==============================================================================
# 7. Verify
# ==============================================================================
echo ""
echo "======================================================================"
echo "  Docker installation complete!"
echo "======================================================================"
echo ""
echo "  Installed version:"
docker --version
if command -v docker-compose &>/dev/null; then
    echo "  Compose  : $(docker-compose version --short 2>/dev/null || docker compose version)"
fi
echo ""
echo "  Service status:"
echo "    sudo systemctl status docker"
echo ""
echo "  To use Docker without sudo, add your user to the docker group:"
echo "    sudo usermod -aG docker \$USER"
echo "    # then log out and back in (or run: newgrp docker)"
echo ""
echo "  Smoke test (requires network or a local image):"
echo "    docker info"
echo ""
