#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# Configuration (SERVER/HEADLESS image)
# Server counterpart of custom-image-setup.sh (desktop). Builds from
# Dockerfile.server and produces custom-server.raw.gz.
IMAGE_NAME="custom-server-custom"
DOCKERFILE="Dockerfile.server"
DOCKERFILE_DIR="."
BUILD_DIR="./build"
RAW_IMG="${BUILD_DIR}/custom-server.raw"
IMG_SIZE="16G"
CONTAINER_EXPORT="${BUILD_DIR}/container_root.tar"
MNT="${BUILD_DIR}/mnt"
KERNEL_SUFFIX="intel"
IMAGE_REBUILD="${HOST_OS_REBUILD:-false}"
IMAGE_TAG_MISSING="false"
# FIX_SWAP_RESUME_BEGIN
# Set ENABLE_SWAP_RESUME=1 to add resume=UUID=<swap-uuid> to kernel cmdline
# This enables hibernation/resume from swap partition.
ENABLE_SWAP_RESUME="${ENABLE_SWAP_RESUME:-0}"
# FIX_SWAP_RESUME_END

# User credentials — must be set via environment variables (see README).
# Generate the SHA-512 password hash with:
#   export USERNAME='<your-username>'
#   export PASSWORD="$(openssl passwd -6 '<your-password>')"
IMAGE_USERNAME="${USERNAME:-}"
IMAGE_USER_PASSWORD="${PASSWORD:-}"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "\n${GREEN}=== $* ===${NC}"; }
error() { echo -e "\n${RED}ERROR: $*${NC}" >&2; exit 1; }


# Cleanup — Loop devices
LOOP_DEV=""
USING_KPARTX=false

cleanup() {
    log "Cleanup: unmounting and detaching loop device"
    # Bind mounts first (reverse order)
    for dir in run sys proc dev/pts dev; do
        sudo umount -l "${MNT}/${dir}" 2>/dev/null || true
    done
    #  EFI before root
    sudo umount -l "${MNT}/boot/efi" 2>/dev/null || true
    # Root last
    sudo umount -l "${MNT}" 2>/dev/null || true
    # Detach loop device
    if [[ -n "${LOOP_DEV}" ]]; then
        if [[ "${USING_KPARTX}" == "true" ]]; then
            sudo kpartx -dv "${LOOP_DEV}" 2>/dev/null || true
        fi
        sudo losetup -d "${LOOP_DEV}" 2>/dev/null || true
    fi
}
trap cleanup EXIT
# Cleanup — Stale loop devices and mounts from previous runs
for ld in $(sudo losetup -j "${RAW_IMG}" 2>/dev/null | cut -d: -f1); do
    log "  Detaching stale loop device: ${ld}"
    sudo kpartx -dv "${ld}" 2>/dev/null || true
    sudo losetup -d "${ld}" 2>/dev/null || true
done

if mountpoint -q "${MNT}" 2>/dev/null; then
    log "  Unmounting stale mounts under ${MNT}"
    sudo umount -lR "${MNT}" 2>/dev/null || true
fi

sudo rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
log "  Build directory clean: ${BUILD_DIR}"

# Validate user credentials are provided
if [[ -z "${IMAGE_USERNAME}" || -z "${IMAGE_USER_PASSWORD}" ]]; then
    error "USERNAME and PASSWORD environment variables must be set.\n" \
          "  export USERNAME='<your-username>'\n" \
          "  export PASSWORD=\"\$(openssl passwd -6 '<your-password>')\""
fi

# Start the build process from where script stoped previously.
# shellcheck disable=SC2046
docker rm -f $(docker ps -aq --filter "ancestor=${IMAGE_NAME}:latest") 2>/dev/null || true

# Build the Ubuntu desktop image
log "Build Docker image"

if ! docker image inspect "${IMAGE_NAME}:latest" >/dev/null 2>&1; then
    IMAGE_TAG_MISSING="true"
    log "  Local image tag ${IMAGE_NAME}:latest not found: forcing no-cache rebuild"
fi

if [[ "${IMAGE_REBUILD}" == "true" || "${IMAGE_TAG_MISSING}" == "true" ]]; then
    if [[ "${IMAGE_REBUILD}" == "true" ]]; then
        log "  HOST_OS_REBUILD=true: forcing no-cache rebuild"
    fi
    # TODO_REMOVE_TLS_WORKAROUND_BEGIN
    # Remove the 3 ALLOW_INSECURE/INTERNAL_CA build-args below when switching
    # to external/publicly trusted Artifactory (no internal CA needed).
    # Grep for TODO_REMOVE_TLS_WORKAROUND to find all related lines.
    # TODO_REMOVE_TLS_WORKAROUND_END
    DOCKER_BUILDKIT=1 docker build \
        --network=host \
        --no-cache \
        --build-arg http_proxy="${http_proxy:-}" \
        --build-arg https_proxy="${https_proxy:-}" \
        --build-arg no_proxy="${no_proxy:-}" \
        --build-arg ALLOW_INSECURE_INTERNAL_REPO_TLS="${ALLOW_INSECURE_INTERNAL_REPO_TLS:-1}" \
        --build-arg INTERNAL_CA_CERT_B64="${INTERNAL_CA_CERT_B64:-}" \
        --build-arg INTERNAL_CA_CERT_FILE="${INTERNAL_CA_CERT_FILE:-}" \
        --build-arg USERNAME="${IMAGE_USERNAME}" \
        --build-arg USER_PASSWORD="${IMAGE_USER_PASSWORD}" \
        -f "${DOCKERFILE}" \
        -t "${IMAGE_NAME}:latest" \
        "${DOCKERFILE_DIR}"
else
    # TODO_REMOVE_TLS_WORKAROUND_BEGIN
    # Remove the 3 ALLOW_INSECURE/INTERNAL_CA build-args below when switching
    # to external/publicly trusted Artifactory (no internal CA needed).
    # Grep for TODO_REMOVE_TLS_WORKAROUND to find all related lines.
    # TODO_REMOVE_TLS_WORKAROUND_END
    DOCKER_BUILDKIT=1 docker build \
        --network=host \
        --build-arg http_proxy="${http_proxy:-}" \
        --build-arg https_proxy="${https_proxy:-}" \
        --build-arg no_proxy="${no_proxy:-}" \
        --build-arg ALLOW_INSECURE_INTERNAL_REPO_TLS="${ALLOW_INSECURE_INTERNAL_REPO_TLS:-1}" \
        --build-arg INTERNAL_CA_CERT_B64="${INTERNAL_CA_CERT_B64:-}" \
        --build-arg INTERNAL_CA_CERT_FILE="${INTERNAL_CA_CERT_FILE:-}" \
        --build-arg USERNAME="${IMAGE_USERNAME}" \
        --build-arg USER_PASSWORD="${IMAGE_USER_PASSWORD}" \
        -f "${DOCKERFILE}" \
        -t "${IMAGE_NAME}:latest" \
        "${DOCKERFILE_DIR}"
fi

log "Export container rootfs"

CONTAINER_ID=$(docker create "${IMAGE_NAME}:latest")
docker export "${CONTAINER_ID}" -o "${CONTAINER_EXPORT}"
docker rm "${CONTAINER_ID}"
log "  Exported: ${CONTAINER_EXPORT} ($(du -sh "${CONTAINER_EXPORT}" | cut -f1))"

log "Detect kernel and initrd from tarball"
VMLINUZ_NAME=$(tar -tf "${CONTAINER_EXPORT}" \
    | grep "^boot/vmlinuz-" \
    | grep -v "^boot/vmlinuz-${KERNEL_SUFFIX}$" \
    | grep "\-${KERNEL_SUFFIX}$" \
    | sort -V | tail -1 \
    | sed 's|boot/||')

INITRD_NAME=$(tar -tf "${CONTAINER_EXPORT}" \
    | grep "^boot/initrd.img-" \
    | grep -v "^boot/initrd.img-${KERNEL_SUFFIX}$" \
    | grep "\-${KERNEL_SUFFIX}$" \
    | sort -V | tail -1 \
    | sed 's|boot/||')

[[ -z "${VMLINUZ_NAME}" ]] && error "Could not detect versioned ${KERNEL_SUFFIX} kernel in tarball"
[[ -z "${INITRD_NAME}"  ]] && error "Could not detect versioned ${KERNEL_SUFFIX} initrd in tarball"

KERNEL_VERSION="${VMLINUZ_NAME#vmlinuz-}"


log "Create raw disk image (${IMG_SIZE})"
truncate -s "${IMG_SIZE}" "${RAW_IMG}"
log "  Created: ${RAW_IMG}"

# Create GPT partition table: 512MB EFI + 4GB swap + rest root
log "Partition (GPT: 512MB EFI + 4GB swap + rest root)"

sgdisk -Z \
    -n 1:0:+512M -t 1:ef00 -c 1:"EFI-SYSTEM" \
    -n 2:0:+4G   -t 2:8200 -c 2:"SWAP"        \
    -n 3:0:0     -t 3:8300 -c 3:"LINUX-ROOT"   \
    -p "${RAW_IMG}"

# Attach loop device and get partition paths
log "Attach loop device"

LOOP_DEV=$(sudo losetup -f --show -P "${RAW_IMG}")
EFI_PART="${LOOP_DEV}p1"
SWAP_PART="${LOOP_DEV}p2"
ROOT_PART="${LOOP_DEV}p3"

# Wait for partition nodes (udev may be slow inside Docker)
for _retry in $(seq 1 10); do
    [[ -b "${EFI_PART}" && -b "${SWAP_PART}" && -b "${ROOT_PART}" ]] && break
    sudo partprobe "${LOOP_DEV}" 2>/dev/null || true
    sleep 1
done

# Fallback to kpartx if losetup -P didn't create partition nodes
if [[ ! -b "${EFI_PART}" || ! -b "${SWAP_PART}" || ! -b "${ROOT_PART}" ]]; then
    log "  losetup -P partition nodes missing — falling back to kpartx"
    # Remove any stale device-mapper entries for this loop device first
    sudo kpartx -dv "${LOOP_DEV}" 2>/dev/null || true
    sudo kpartx -av "${LOOP_DEV}"
    sudo udevadm settle 2>/dev/null || sleep 2
    USING_KPARTX=true
    EFI_PART="/dev/mapper/$(basename "${LOOP_DEV}")p1"
    SWAP_PART="/dev/mapper/$(basename "${LOOP_DEV}")p2"
    ROOT_PART="/dev/mapper/$(basename "${LOOP_DEV}")p3"
    for _retry in $(seq 1 10); do
        [[ -b "${EFI_PART}" && -b "${SWAP_PART}" && -b "${ROOT_PART}" ]] && break
        sleep 1
    done
fi

[[ ! -b "${EFI_PART}"  ]] && error "EFI partition device ${EFI_PART} not found"
[[ ! -b "${SWAP_PART}" ]] && error "Swap partition device ${SWAP_PART} not found"
[[ ! -b "${ROOT_PART}" ]] && error "Root partition device ${ROOT_PART} not found"



log "Format partitions with rootfs, swap, and EFI filesystems"
sudo partprobe "${LOOP_DEV}" 2>/dev/null || true
sleep 2
[[ ! -b "${EFI_PART}"  ]] && error "EFI partition device ${EFI_PART} disappeared before format"
[[ ! -b "${SWAP_PART}" ]] && error "Swap partition device ${SWAP_PART} disappeared before format"
[[ ! -b "${ROOT_PART}" ]] && error "Root partition device ${ROOT_PART} disappeared before format"
sudo mkfs.vfat -F 32 -n "EFI"  "${EFI_PART}"
sudo mkswap -L "SWAP" "${SWAP_PART}"
sudo mkfs.ext4 -F    -L "ROOT" "${ROOT_PART}"

ROOT_UUID=$(sudo blkid -o value -s UUID     "${ROOT_PART}")
EFI_UUID=$( sudo blkid -o value -s UUID     "${EFI_PART}")
SWAP_UUID=$(sudo blkid -o value -s UUID     "${SWAP_PART}")
ROOT_PARTUUID=$(sudo blkid -o value -s PARTUUID "${ROOT_PART}")
# EFI_PARTUUID reserved for future use (e.g. fstab generation)
# shellcheck disable=SC2034
EFI_PARTUUID=$( sudo blkid -o value -s PARTUUID "${EFI_PART}")

[[ -z "${ROOT_UUID}"     ]] && error "ROOT_UUID is empty — blkid failed"
[[ -z "${ROOT_PARTUUID}" ]] && error "ROOT_PARTUUID is empty — blkid failed"

log "Mount and extract rootfs"
mkdir -p "${MNT}"
sudo mount -t ext4 "${ROOT_PART}" "${MNT}"
sudo mkdir -p "${MNT}/boot/efi"
sudo mount "${EFI_PART}" "${MNT}/boot/efi"

# Verify both are mounted before proceeding
mountpoint -q "${MNT}"          || error "Root partition not mounted at ${MNT}"
mountpoint -q "${MNT}/boot/efi" || error "EFI partition not mounted at ${MNT}/boot/efi"

log "  Extracting tarball (this may take a while)..."
sudo tar -xpf "${CONTAINER_EXPORT}" -C "${MNT}" --numeric-owner
log "  Extraction complete"

log "Fix runtime configuration on mounted image"


if [[ -e "${MNT}/.dockerenv" ]]; then
    sudo rm -f "${MNT}/.dockerenv"
    log "  Removed ${MNT}/.dockerenv"
fi

# Remove default ubuntu user name



# Remove default ubuntu user name 
sudo chroot "${MNT}" userdel -r ubuntu >/dev/null 2>&1 || true

# Fix resolv.conf — remove Docker's copy, replace with systemd-resolved symlink
sudo rm -f "${MNT}/etc/resolv.conf"
sudo ln -sf /run/systemd/resolve/stub-resolv.conf "${MNT}/etc/resolv.conf"
log "  resolv.conf -> $(sudo readlink ${MNT}/etc/resolv.conf)"


# Fix hostname and hosts file
sudo tee "${MNT}/etc/hostname" > /dev/null << 'EOF'
minimal-ubuntu-server
EOF

sudo tee "${MNT}/etc/hosts" > /dev/null << 'EOF'
127.0.0.1   localhost
127.0.1.1   minimal-ubuntu-server
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF
log "  hostname and hosts file written"



sudo tee "${MNT}/etc/apt/sources.list.d/ubuntu.sources" > /dev/null << 'EOF'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

sudo tee "${MNT}/etc/sysctl.d/99-dmesg.conf" > /dev/null << 'EOF'
kernel.dmesg_restrict = 0
EOF

sudo grep -rl "dmesg" "${MNT}/etc/profile.d/" 2>/dev/null | while read -r f; do
    log "  Patching dmesg call in: ${f}"
    sudo sed -i 's/^\(.*dmesg.*\)$/# \1 # disabled — dmesg_restrict/' "${f}"
done || true

# Fix /etc/profile.d scripts
sudo sed -i 's|^\(.*\. "$i".*\)$|{ \1; } 2>/dev/null \|\| true|g' "${MNT}/etc/profile"
sudo grep "profile.d" "${MNT}/etc/profile" || true

# Fix mesa_driver.sh — if line was commented out leaving orphaned else/fi
sudo tee "${MNT}/etc/profile.d/mesa_driver.sh" > /dev/null << 'EOF'
#!/bin/sh
# Mesa driver selection based on SR-IOV VF detection
if dmesg 2>/dev/null | grep -q "SR-IOV VF"; then
    export MESA_LOADER_DRIVER_OVERRIDE=pl111
else
    export MESA_LOADER_DRIVER_OVERRIDE=iris
fi
EOF


# Write to fstab with UUIDs for root, swap, and EFI partitions
log "Write fstab"
sudo tee "${MNT}/etc/fstab" > /dev/null << EOF
# <file system>        <mount point>  <type>  <options>           <dump> <pass>
UUID=${ROOT_UUID}      /              ext4    errors=remount-ro   0      1
UUID=${EFI_UUID}       /boot/efi      vfat    defaults            0      2
UUID=${SWAP_UUID}      none           swap    sw                  0      0
EOF
log "  fstab written:"
sudo cat "${MNT}/etc/fstab"

# Bind-mount virtual filesystems for chroot environment
log "Bind-mount virtual filesystems"
for dir in dev dev/pts proc sys run; do
    sudo mkdir -p "${MNT}/${dir}"
    sudo mount --bind "/${dir}" "${MNT}/${dir}"
done
KERNEL_VERSION=$(find "${MNT}/lib/modules" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort | head -n 1)

# Verify we found a valid version directory, then run the tool correctly
if [ -n "$KERNEL_VERSION" ]; then
    echo "Found kernel version: $KERNEL_VERSION. Generating initramfs..."
else
    echo "ERROR: No kernel modules found in /lib/modules!"
fi
log "Ensure initramfs tools are present in chroot"
if ! sudo chroot "${MNT}" bash -lc 'command -v update-initramfs >/dev/null 2>&1'; then
    log "  update-initramfs not found, installing initramfs-tools"
    sudo chroot "${MNT}" bash -lc 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y initramfs-tools'
fi

log "Regenerate initramfs for all kernels in target rootfs"
sudo chroot "${MNT}" update-initramfs -u -k "$KERNEL_VERSION"

# Install GRUB
log "Install GRUB"

sudo grub-install \
    --target=x86_64-efi \
    --efi-directory="${MNT}/boot/efi" \
    --boot-directory="${MNT}/boot/efi" \
    --bootloader-id=Ubuntu \
    --removable \
    --recheck \
    --no-nvram

# Verify modules landed on EFI partition
GRUB_CFG_DIR=$(sudo find "${MNT}/boot/efi" -name "*.mod" -type f 2>/dev/null \
    | head -1 | xargs dirname 2>/dev/null | sed 's|/x86_64-efi||' || true)
[[ -z "${GRUB_CFG_DIR}" ]] && die "GRUB modules missing from EFI partition — grub-install failed"
log "  GRUB modules at : ${GRUB_CFG_DIR}"

# Grub config for booting the image
mountpoint -q "${MNT}/boot/efi" || die "EFI partition not mounted"

# FIX_SWAP_RESUME_BEGIN
# Build kernel cmdline with optional swap resume parameter
KERNEL_CMDLINE="root=PARTUUID=${ROOT_PARTUUID} ro rootdelay=5 console=tty0 console=ttyS0,115200n8 \"xe.force_probe=*\" xe.max_vfs=7 modprobe.blacklist=i915 udmabuf.list_limit=8192"
if [[ "${ENABLE_SWAP_RESUME}" == "1" ]]; then
    KERNEL_CMDLINE="${KERNEL_CMDLINE} resume=UUID=${SWAP_UUID}"
    log "  Swap resume enabled: resume=UUID=${SWAP_UUID}"
fi
# FIX_SWAP_RESUME_END

sudo mkdir -p "${GRUB_CFG_DIR}"
sudo tee "${GRUB_CFG_DIR}/grub.cfg" > /dev/null << EOF

set default=0
set timeout=5

insmod part_gpt
insmod ext2
insmod search
insmod search_fs_uuid

search --no-floppy --set=root --fs-uuid ${ROOT_UUID}

menuentry "Ubuntu Server (${KERNEL_VERSION})" {
    linux  /boot/${VMLINUZ_NAME} ${KERNEL_CMDLINE}
    initrd /boot/${INITRD_NAME}
}

menuentry "Ubuntu Server (recovery)" {
    linux  /boot/${VMLINUZ_NAME} root=PARTUUID=${ROOT_PARTUUID} ro single rootdelay=5 console=tty0 console=ttyS0,115200n8
    initrd /boot/${INITRD_NAME}
}
EOF

log "  grub.cfg written at: ${GRUB_CFG_DIR}/grub.cfg"
sudo grep -E "search|linux |initrd " "${GRUB_CFG_DIR}/grub.cfg"

# Unmount virtual filesystems before compressing
log "Unmount bind mounts (reverse order)"
for dir in run sys proc dev/pts dev; do
    sudo umount "${MNT}/${dir}" || sudo umount -l "${MNT}/${dir}" || true
done

# Unmount everything before compressing
sudo umount "${MNT}/boot/efi" || sudo umount -l "${MNT}/boot/efi" || true
sudo umount "${MNT}"          || sudo umount -l "${MNT}"          || true

# Detach loop device before compressing
if [[ "${USING_KPARTX}" == "true" ]]; then
    sudo kpartx -dv "${LOOP_DEV}" 2>/dev/null || true
fi
sudo losetup -d "${LOOP_DEV}" 2>/dev/null || true
LOOP_DEV=""  # Prevent cleanup from trying to detach again

# Compress the raw image with pigz for faster compression
log "  Compressing image with pigz..."
if ! pigz -3 -p "$(nproc)" -k "${RAW_IMG}"; then
    error "pigz compression failed"
fi
log "  Compressed: ${RAW_IMG}.gz ($(du -sh "${RAW_IMG}.gz" | cut -f1))"

# ===========================================================================
log "BUILD COMPLETE"
# ===========================================================================
echo ""
echo "  Image         : ${RAW_IMG}  ($(du -sh "${RAW_IMG}" | cut -f1))"
echo "  Compressed    : ${RAW_IMG}.gz  ($(du -sh "${RAW_IMG}.gz" | cut -f1))"
