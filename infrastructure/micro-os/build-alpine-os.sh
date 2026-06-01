#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail


## Configuration


# Alpine configuration
ALPINE_VERSION="3.14"
ARCH="x86_64"
MIRROR="https://dl-cdn.alpinelinux.org/alpine"

# Directory paths
WORKDIR="$(pwd)/build"
ROOTFS="$WORKDIR/rootfs"
OUT="$WORKDIR/output"

## Provisioning files
OS_INSTALLER_SCRIPT="$(pwd)/../provisioning-scripts/install-os.sh"

# If new files need to be added for provisioning, update the FILES_LIST below with corresponding paths
readonly -a FILES_LIST=(
    "$(pwd)/../provisioning-scripts/os-partition.sh"
    "$(pwd)/../provisioning-scripts/cloud-init.yaml"
    "$(pwd)/../installation-scripts/kubernetes-provision.sh"
    "$(pwd)/../installation-scripts/container-provision.sh"
    "$(pwd)/../installation-scripts/install-intel-device-plugins.sh"
    "$(pwd)/../installation-scripts/install-helm.sh"
    "$(pwd)/../installation-scripts/container_setup_sriov.sh"
    "$(pwd)/../installation-scripts/setup-kernel-depended-pkgs.sh"
    "$(pwd)/../installation-scripts/resources/intel-device-plugins/manifests/nfd.yaml"
    "$(pwd)/../installation-scripts/resources/intel-device-plugins/manifests/nfd-node-feature-rules.yaml"
    "$(pwd)/../installation-scripts/resources/intel-device-plugins/manifests/gpu-plugin.yaml"
    "$(pwd)/../installation-scripts/resources/intel-device-plugins/manifests/npu-plugin.yaml"
)
readonly -a CDI_FILES_LIST=(
    "$(pwd)/../installation-scripts/cdi"
)

## Packages to install in Alpine
readonly PACKAGES="busybox util-linux linux-lts e2fsprogs e2fsprogs-static dosfstools parted sgdisk bc lvm2  bash blkid e2fsprogs-extra cryptsetup iproute2 kmod net-tools pciutils eudev efibootmgr dialog"

## Functions

# Cleaning mounts
cleanup() {
    echo "[*] Cleaning mounts..."
    sudo umount -lf "$ROOTFS/dev" 2>/dev/null || true
    sudo umount -lf "$ROOTFS/proc" 2>/dev/null || true
    sudo umount -lf "$ROOTFS/sys" 2>/dev/null || true
}

# Mounting pseudo filesystems
mount_filesystems() {
    sudo mount --bind /dev "$ROOTFS/dev"
    sudo mount --bind /proc "$ROOTFS/proc"
    sudo mount --bind /sys "$ROOTFS/sys"
}

# Download and extract Alpine rootfs
download_and_extract_rootfs() {
    echo "Downloading Alpine minirootfs..."
    cd "$WORKDIR"
    wget -q "$MIRROR/v$ALPINE_VERSION/releases/$ARCH/alpine-minirootfs-$ALPINE_VERSION.0-$ARCH.tar.gz"
    
    echo "Extracting..."
    tar -xzf alpine-minirootfs-*.tar.gz -C "$ROOTFS"
}

# Configure Alpine repositories and network
setup_repositories() {
    echo "$MIRROR/v$ALPINE_VERSION/main" > "$ROOTFS/etc/apk/repositories"
    echo "$MIRROR/v$ALPINE_VERSION/community" >> "$ROOTFS/etc/apk/repositories"
}

# Copy network config
copy_network_config() {
    cp /etc/resolv.conf "$ROOTFS/etc/" || true
}

# Install required packages
install_packages() {
    echo "Installing packages inside rootfs..."
    sudo chroot "$ROOTFS" /bin/sh -c "apk update && apk add $PACKAGES"
}

# Copy installer and provisioning scripts
copy_installer_script() {
    echo "Copying installer script..."
    sudo mkdir -p "$ROOTFS/usr/local/bin"
    sudo cp "$OS_INSTALLER_SCRIPT" "$ROOTFS/usr/local/bin/os-install.sh"
    sudo chmod +x "$ROOTFS/usr/local/bin/os-install.sh"
}

# Copy provisioning files
copy_provisioning_files() {
    echo "Copying provisioning extra files..."
    sudo mkdir -p "$ROOTFS/etc/scripts/"
    sudo mkdir -p "$ROOTFS/etc/scripts/cdi"
     
    for item in "${FILES_LIST[@]}"; do
        if [[ -e "$item" ]]; then
            sudo cp -r "$item" "$ROOTFS/etc/scripts/"
        else
            echo "[WARN] Skipping missing: $item"
        fi
    done

    # Copy cdi scripts 
    for item in "${CDI_FILES_LIST[@]}"; do
        if [[ -e "$item" ]]; then
	    sudo cp -r "$item/." "$ROOTFS/etc/scripts/cdi/"
        else
            echo "[WARN] Skipping missing: $item"
        fi
    done

}

# Create init script
create_init_script() {
    echo "Creating init script..."
    sudo tee "$ROOTFS/init" >/dev/null << 'EOF'
#!/bin/sh
mkdir -p /proc /sys /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null

# Ensure critical devices
[ -e /dev/null ]    || mknod -m 666 /dev/null    c 1 3
[ -e /dev/console ] || mknod -m 600 /dev/console c 5 1
[ -e /dev/tty1 ]    || mknod -m 620 /dev/tty1    c 4 1
[ -e /dev/ttyS0 ]   || mknod -m 620 /dev/ttyS0   c 4 64

mdev -s
depmod -a 2>/dev/null

# Storage
modprobe sd_mod    2>/dev/null
modprobe ahci      2>/dev/null
modprobe nvme      2>/dev/null
modprobe nvme-core 2>/dev/null
modprobe vmd       2>/dev/null
modprobe virtio_blk 2>/dev/null

# USB stack — ORDER MATTERS
modprobe xhci-pci  2>/dev/null
modprobe ehci-pci  2>/dev/null
modprobe usb-storage 2>/dev/null
modprobe uas       2>/dev/null

#  Keyboard input drivers
modprobe hid       2>/dev/null
modprobe hid_generic 2>/dev/null
modprobe usbhid    2>/dev/null
modprobe i8042     2>/dev/null
modprobe atkbd     2>/dev/null
modprobe evdev     2>/dev/null
modprobe efivars  2>/dev/null

sleep 5

# Run installer
/usr/local/bin/os-install.sh

#  Proper interactive terminal (loops so it respawns)
while true; do
    /sbin/agetty --autologin root --noclear 0 tty1 linux
done
EOF
    sudo chmod +x "$ROOTFS/init"
}

# Copy kernel
copy_kernel() {

    sudo cp "$ROOTFS/boot/vmlinuz-lts" "$OUT/vmlinuz"

    if [ ! -d "$ROOTFS/lib/modules" ]; then
        echo "ERROR: No modules found in rootfs! Check apk add linux-lts step."
        exit 1
    fi
    cd - >/dev/null
}

# Build initramfs
build_initramfs() {
    echo "Building initramfs..."
    cd "$ROOTFS"
    find . \
        -path ./proc -prune -o \
        -path ./sys -prune -o \
        -path ./dev -prune -o \
        -print | cpio -o -H newc | gzip > "$OUT/initramfs"
    cd - >/dev/null
}

# Verify build success
verify_build() {
    if [[ -e "$OUT/initramfs" && -e "$OUT/vmlinuz" ]]; then
        echo "Build complete!"
    else
        echo "Build failed! Please check!"
        exit 1
    fi
}

## @Main Script

trap cleanup EXIT

# Initialize build directories
rm -rf "$WORKDIR"
mkdir -p "$ROOTFS" "$OUT"

# Download and extract Alpine rootfs
download_and_extract_rootfs

# Configure Alpine repositories and network
setup_repositories
copy_network_config

# Mount filesystems for chroot environment
mount_filesystems

# Install required packages
install_packages

# Copy installer and provisioning scripts
copy_installer_script
copy_provisioning_files

# Create init script
create_init_script

# Copy kernel
copy_kernel

# Build initramfs
build_initramfs

# Verify build success
verify_build

