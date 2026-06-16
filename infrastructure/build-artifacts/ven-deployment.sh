#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

#########################################################################
#
# This script to setup the Ubuntu image installation  on virtual edge node.
# It will speed up the developer PR verification and real h/w limitations
#
#########################################################################
set -e

new_img=""

# Kill any VMs launched by a prior run of this script
if pgrep -f "qemu-system-x86_64.*ubuntu-disk\.img" > /dev/null 2>&1; then
    echo "Killing qemu-system-x86_64 instance(s) from a prior run of this script..."
    pkill -f "qemu-system-x86_64.*ubuntu-disk\.img" || true
    sleep 1
fi

# Disconnect any leftover nbd0 connection from a prior run
if [ -e /sys/block/nbd0/pid ]; then
    echo "Disconnecting leftover nbd0 device..."
    qemu-nbd --disconnect /dev/nbd0 || true
fi

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Please run this script with sudo!"
    exit 1
fi

# if Custom image update
if [ -n "$1" ]; then
    if echo "$1" | grep -qE '\.gz$'; then
        new_img=$1
    else
        echo "Error: Ubuntu image is not a .gz file"
        exit 1
    fi
fi
# Install qemu-system 
if ! dpkg -s qemu-system-x86 >/dev/null 2>&1; then
    echo  "Installing qemu-system-x86.., Please Wait!!"
    apt update
    if ! apt install -y qemu-system-x86 >/dev/null 2>&1; then
        echo "Qemu Installation Failed,Please check!!"
        exit 1
    fi	
else
    echo  "Qemu already installed Skipping it"

fi

if ! dpkg -s net-tools >/dev/null 2>&1; then
   apt install net-tools -y
fi

pub_interface_name=$(route | grep '^default' | grep -o '[^ ]*$')
host_ip=$(ifconfig "${pub_interface_name}" | grep 'inet ' | awk '{print $2}')


# Create the virtual usb disk
if [ -e usb-disk ]; then
    rm -rf usb-disk
fi
qemu-img create -f qcow2 usb-disk 64G > /dev/null 2>&1 || { echo "virtual usb device failed to create,please check"; exit 1; } 

echo "virtual-usb of size 64GB created successfully"

# Bind/Mount the virtual usb disk to qemu network block device
# Number of partitions on the virtual disk
modprobe nbd max_part=8

if [ ! -e /sys/block/nbd0/pid ]; then
    echo "Connecting usb-disk..."
    qemu-nbd --connect=/dev/nbd0 usb-disk
fi

# Prepare the USB bootable device. /dev/nbd0 is the virtual usb device.
if [  -z "$new_img" ]; then

    ./bootable-usb-prepare.sh /dev/nbd0 usb-bootable-files.tar.gz config-file || { echo "USB device setup failed,please check"; exit 1; }

else
    ./bootable-usb-prepare.sh /dev/nbd0 usb-bootable-files.tar.gz config-file $new_img || { echo "USB device setup failed,please check"; exit 1; }

fi

# Launch the VM for Ubuntu Image installation
# Create the ubuntu-disk.img for installation

if [ -e ubuntu-disk.img ]; then
    rm -rf ubuntu-disk.img
fi
qemu-img create -f qcow2 ubuntu-disk.img 64G > /dev/null 2>&1 || { echo "creating emt disk image failed to create,please check"; exit 1; }

echo "Starting the Installation"
echo ""
echo "Please see the installation status on VNC viewer.Enter $host_ip:5999 on vnc viewer"
# Added -cpu host,+vms It will support nested VM configuration as well
if ! sudo -E qemu-system-x86_64  \
  -m 4G   -enable-kvm  \
  -cpu host,+vmx \
  -machine q35,accel=kvm \
  -bios /usr/share/qemu/OVMF.fd  \
  -vnc :99 \
  -drive file=ubuntu-disk.img,format=qcow2 \
  -device usb-ehci,id=ehci  \
  -device usb-storage,bus=ehci.0,drive=usb,removable=on  \
  -drive file=/dev/nbd0,format=raw,id=usb,if=none; then
    echo "Installation VM launch Failed,Please check!!"
fi

trap 'killall --quiet standalone-vm-launch.sh || true' EXIT 
