#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

####################################################
#
# File Name: Prepare_Ubuntu_Image.sh
# Details: This script is to generate Ubuntu RAW
#          Image from ISO file
#
###################################################
#set -x
set -e

# --- Configuration ---
ISO_URL=""
OUTPUT_IMG="ubuntu-desktop-24.04.raw.img"
USER_DATA=""
INSTALLER_SCRIPT=""
SEED_ISO="seed.iso"
DISK_SIZE="20G"
TEMP_USER_DATA=""


# Check root
if [ "$EUID" -ne 0 ]; then
     echo "Please run as root (use sudo)"
    exit 1
fi

usage() {
    echo "Usage : `basename $0` -i <iso_link> -c auto-install-pkgs.yaml [-s installer.sh]"
    echo "Options are below"
    echo "  -i , --isolink  | provide the iso artifactory link"
    echo "  -c , --configuration file | provide the auto-install-pkgs.yaml file"
}

cleanup() {
    if [ -n "$TEMP_USER_DATA" ] && [ -f "$TEMP_USER_DATA" ]; then
        rm -f "$TEMP_USER_DATA"
    fi
}

trap cleanup EXIT

while getopts "i:c:s:h:" option
do
    case "$option" in
    i) ISO_URL="$OPTARG" ;;
    c) USER_DATA="$OPTARG" ;;
    h|?) usage
        exit 0
    ;;
    esac
done

# Validate required arguments
if [ -z "$ISO_URL" ] || [ -z "$USER_DATA" ]; then
    echo "Error: Both -i (ISO URL) and -c (config file) are required"
    usage
    exit 1
fi

if [ ! -f "$USER_DATA" ]; then
    echo "Error: Config file not found: $USER_DATA"
    exit 1
fi

USER_DATA_DIR=$(cd "$(dirname "$USER_DATA")" && pwd)
USER_DATA_FILE=$(basename "$USER_DATA")

INSTALLER_SCRIPT="$USER_DATA_DIR/installer.sh"

if [ -n "$INSTALLER_SCRIPT" ] && [ ! -f "$INSTALLER_SCRIPT" ]; then
    echo "Error: Installer script not found: $INSTALLER_SCRIPT"
    exit 1
fi

#  Install dependency pkgs ---
echo "Installing dependencies..."
sudo apt update && sudo apt install -y qemu-system-x86 qemu-utils xorriso cloud-image-utils wget dosfstools e2fsprogs parted coreutils > /dev/null 2>&1 

ISO_FILE=$(basename "$ISO_URL")

# Download ISO ---
if [ ! -f "$ISO_FILE" ]; then
    echo "Downloading Ubuntu $ISO_FILE..."
    wget -O "$ISO_FILE" "$ISO_URL"
fi

#  Extract vmlinuz and initrd ---
echo "Extracting boot files from ISO..."
mkdir -p ./iso_mount
sudo mount -o loop "$ISO_FILE" ./iso_mount
cp ./iso_mount/casper/vmlinuz .
cp ./iso_mount/casper/initrd .
sudo umount ./iso_mount
rmdir ./iso_mount

#  Prepare Build Files ---
echo "Creating seed ISO and blank disk..."
touch meta-data

# Update the auto-install-pkgs.yaml to add CBKC Scripts
USER_DATA_SOURCE="$USER_DATA"

if [ -n "$INSTALLER_SCRIPT" ]; then
        echo "Attaching installer script: $INSTALLER_SCRIPT"
        INSTALLER_B64=$(base64 -w 0 "$INSTALLER_SCRIPT")
        TEMP_USER_DATA=$(mktemp)

        awk -v installer_b64="$INSTALLER_B64" '
            /^    write_files:$/ && !inserted {
                print
                print "    - path: /usr/local/bin/installer.sh"
                print "      owner: root:root"
                print "      permissions: '\''0755'\''"
                print "      encoding: b64"
                print "      content: " installer_b64
                inserted=1
                next
            }
            { print }
            END {
                if (!inserted) {
                    exit 1
                }
            }
        ' "$USER_DATA" > "$TEMP_USER_DATA" || {
                echo "Error: Failed to inject installer.sh into $USER_DATA_FILE"
                exit 1
        }

        USER_DATA_SOURCE="$TEMP_USER_DATA"
fi

cloud-localds "$SEED_ISO" "$USER_DATA_SOURCE" meta-data
if [ -f "$OUTPUT_IMG" ]; then
    rm -rf "$OUTPUT_IMG"
    rm -rf "$OUTPUT_IMG".gz > /dev/null 2>&1
    rm -rf "$OUTPUT_IMG"* > /dev/null 2>&1
fi
qemu-img create -f raw "$OUTPUT_IMG" "$DISK_SIZE"

#  Run QEMU Installation ---
echo "Starting Installation (Minimal Desktop)....,It will take 15~20 minutes Please wait!!"

# Get the total CPU cores and allocate more
TOTAL_CPUS=$(nproc)
VM_CPUS=$((TOTAL_CPUS - 2))   # keep 2 cores for host

[ "$VM_CPUS" -lt 1 ] && VM_CPUS=1

# Get the total memory and allocate more
TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
VM_MEM_MB=$((TOTAL_MEM_MB - 2048))   # keep 2GB for host

[ "$VM_MEM_MB" -lt 1024 ] && VM_MEM_MB=1024

# Start QEMU and show progress spinner
qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -m $VM_MEM_MB \
    -smp $VM_CPUS \
    -bios /usr/share/qemu/OVMF.fd \
    -drive file="$OUTPUT_IMG",format=raw,if=virtio,cache=none,aio=native \
    -drive file="$ISO_FILE",format=raw,readonly=on,if=virtio \
    -drive file="$SEED_ISO",format=raw,readonly=on,if=virtio \
    -kernel vmlinuz \
    -initrd initrd \
    -append "autoinstall ds=nocloud fsck.mode=skip quiet console=ttyS0 console=tty0" \
    -vnc :99 \
    -no-reboot  >error.log 2>&1 &

QEMU_INSTALL_PID=$!
spin_chars=( '|' '/' '-' '\' )
spin_idx=0
while kill -0 $QEMU_INSTALL_PID 2>/dev/null; do
    echo -ne "\rInstalling... ${spin_chars[$spin_idx]} "
    spin_idx=$(( (spin_idx + 1) % 4 ))
    sleep 0.5
done
wait $QEMU_INSTALL_PID
echo -e "\rInstalling... Done!                  "

sync
sleep 5
sync
echo "Base Installation finished."

# Post-Install: Installing BKC and other packages ---

echo "Installing Packages from BKC,Docker,k3s"
qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -m $VM_MEM_MB \
    -smp $VM_CPUS \
    -bios /usr/share/qemu/OVMF.fd \
    -drive file="$OUTPUT_IMG",format=raw,if=virtio \
    -nographic \
    -vnc :99 >>error.log 2>&1 & 


# Capture the Process ID of QEMU
QEMU_PID=$!

spin_chars=( '|' '/' '-' '\' )
spin_idx=0
while kill -0 $QEMU_PID 2>/dev/null; do
    echo -ne "\rPackage installation... ${spin_chars[$spin_idx]} "
    spin_idx=$(( (spin_idx + 1) % 4 ))
    sleep 0.5
done
wait $QEMU_PID
echo "\rPackage installation... Done!                  "

# Label the partitions for generated Image
echo "Creating the partition labels for the Image"

# Mount image as loop device with partition scanning
LOOP_DEV=$(sudo losetup -Pf --show "$OUTPUT_IMG")

# Wait a second for kernel to register partitions
sleep 2

echo "Applying label 'uefi' to partition 1..."
sudo fatlabel "${LOOP_DEV}p1" uefi || echo "Failed to label p1"

echo "Applying label 'rootfs' to partition 2..."
sudo e2label "${LOOP_DEV}p2" rootfs || echo "Failed to label p2"

# Also set GPT Partition Names for clarity in tools like GParted
sudo parted "${LOOP_DEV}" name 1 uefi
sudo parted "${LOOP_DEV}" name 2 rootfs

# Detach loop device
sudo losetup -d "$LOOP_DEV"

# Cleanup ---
rm vmlinuz initrd "$SEED_ISO" meta-data

# Compress the Image to .gz using pigz
echo "Creating Imge Compression,Please Wait"
if pigz -3 -k "$OUTPUT_IMG"; then
   echo "DONE: $OUTPUT_IMG.gz created successfully."
else
   echo "ERROR: pigz failed."
   exit 1
fi 

# Generate the sha-checksum file
echo "Generating the CheckSum File,Please Wait"

if sha256sum $OUTPUT_IMG.gz >  $OUTPUT_IMG.gz.sha256sum ; then
    echo "Sha256sum generated successfully for the image $OUTPUT_IMG.gz"
else
    echo "Failed to generate the Sha256sum file,Please check!!"
fi

echo "################################################"
echo " Image Creation SUCCESS!"
echo " Raw Image Created: $OUTPUT_IMG.gz"
echo " CheckSum File Created: $OUTPUT_IMG.gz.sha256sum" 
echo " Partition 1 (FAT32): uefi"
echo " Partition 2 (EXT4):  rootfs"
echo "################################################"


