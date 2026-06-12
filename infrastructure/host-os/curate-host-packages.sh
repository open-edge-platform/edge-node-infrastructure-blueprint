#!/bin/bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e 
set -x


#======================================================
#  Edge Node Infrastructure Setup Script
#
# This script will set up the necessary environment 
# for edge node infrastructure development.
#======================================================

install_depended_packages() {
	echo "Updating apt and installing initial packages..."
	sudo apt update
	sudo apt upgrade -y
	sudo apt install ethtool libbpf1 wayland-protocols -y
	echo "Initial packages installed."
}

create_ppa_sources_list() {
	echo "Creating Intel PTL PPA sources list..."
	sudo mkdir -p /etc/apt/sources.list.d
	sudo bash -c 'cat > /etc/apt/sources.list.d/intel-ptl.list << EOF
deb https://download.01.org/intel-linux-overlay/ubuntu noble main non-free multimedia kernels
deb-src https://download.01.org/intel-linux-overlay/ubuntu noble main non-free multimedia kernels
EOF'
    echo "Intel PTL PPA sources list created."
}

download_and_install_gpg_key() {
	echo "Downloading and installing GPG key..."
	sudo wget https://download.01.org/intel-linux-overlay/ubuntu/E6FA98203588250569758E97D176E3162086EE4C.gpg -O /etc/apt/trusted.gpg.d/ptl.gpg
	echo "GPG key installed."
}


set_preferred_package_list() {
	echo "Setting preferred package list..."
	sudo bash -c 'cat > /etc/apt/preferences.d/intel-ptl << EOF
Package: *
Pin: release o=intel-iot-linux-overlay-noble
Pin-Priority: 2000
EOF'
}

install_essential_tools() {
	echo "Installing essential tools and dependencies..."
	sudo apt update
	export DEBIAN_FRONTEND=noninteractive
	sudo apt install -y libigfxcmrt-dev libigfxcmrt7 nano ocl-icd-libopencl1 curl openssh-server net-tools gir1.2-gst-plugins-bad-1.0 gir1.2-gst-plugins-base-1.0 gir1.2-gstreamer-1.0 gir1.2-gst-rtsp-server-1.0 gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-opencv gstreamer1.0-plugins-bad gstreamer1.0-plugins-bad-apps gstreamer1.0-plugins-base gstreamer1.0-plugins-base-apps gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly gstreamer1.0-pulseaudio gstreamer1.0-qt5 gstreamer1.0-rtsp gstreamer1.0-tools gstreamer1.0-x intel-media-va-driver-non-free libdrm-amdgpu1 libdrm-common libdrm-dev libdrm-intel1 libdrm-nouveau2 libdrm-radeon1 libdrm-tests libdrm2 libgstrtspserver-1.0-dev libgstrtspserver-1.0-0 libgstreamer-gl1.0-0 libgstreamer-opencv1.0-0 libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-bad1.0-dev libgstreamer-plugins-base1.0-0 libgstreamer-plugins-base1.0-dev libgstreamer1.0-0 libgstreamer1.0-dev libigdgmm-dev libigdgmm12 libmfx-gen1.2 libtpms-dev libtpms0 libva-dev libva-drm2 libva-glx2 libva-wayland2 libva-x11-2 libva2 libwayland-bin libwayland-client0 libwayland-cursor0 libwayland-dev libwayland-doc libwayland-egl-backend-dev libwayland-egl1 libwayland-server0 linux-firmware mesa-utils mesa-vulkan-drivers libvpl-dev libvpl-tools libmfx-gen-dev onevpl-tools ovmf ovmf-ia32 qemu-block-extra qemu-guest-agent qemu-system qemu-system-arm qemu-system-common qemu-system-data qemu-system-gui qemu-system-mips qemu-system-misc qemu-system-ppc qemu-system-s390x qemu-system-sparc qemu-system-x86 qemu-user qemu-user-binfmt qemu-utils va-driver-all vainfo weston xserver-xorg-core libvirt0 libvirt-clients libvirt-daemon libvirt-daemon-config-network libvirt-daemon-config-nwfilter libvirt-daemon-driver-lxc libvirt-daemon-driver-qemu libvirt-daemon-driver-storage-gluster libvirt-daemon-driver-storage-iscsi-direct libvirt-daemon-driver-storage-rbd libvirt-daemon-driver-storage-zfs libvirt-daemon-driver-vbox libvirt-daemon-driver-xen libvirt-daemon-system libvirt-daemon-system-systemd libvirt-dev libvirt-doc libvirt-login-shell libvirt-sanlock libvirt-wireshark libnss-libvirt swtpm swtpm-tools bmap-tools adb autoconf automake libtool cmake g++ gcc git intel-gpu-tools libssl3 libssl-dev make mosquitto mosquitto-clients build-essential apt-transport-https default-jre docker-compose ffmpeg git-lfs gnuplot lbzip2 libglew-dev libglm-dev libsdl2-dev mc openssl pciutils python3-pandas python3-pip python3-seaborn terminator wmctrl gdbserver iperf3 msr-tools powertop linuxptp lsscsi tpm2-tools tpm2-abrmd binutils cifs-utils i2c-tools xdotool gnupg lsb-release qemu-system-modules-opengl socat virt-viewer spice-client-gtk util-linux-extra dbus-x11 sg3-utils rpm --allow-downgrades
	echo "Essential tools and dependencies installed."
}


install_kernel() {
	echo "Installing Linux kernel..."
	sudo apt install linux-image-6.18-intel linux-headers-6.18-intel -y
	echo "Linux kernel installed."
}

update_grub_configuration() {
	echo "Updating GRUB configuration..."
	sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash xe.max_vfs=7 xe.force_probe=* modprobe.blacklist=i915 udmabuf.list_limit=8192"/' /etc/default/grub
	sudo update-grub
	echo "GRUB configuration updated."
}

main() {
	
    install_depended_packages

    create_ppa_sources_list

    download_and_install_gpg_key

    set_preferred_package_list

    install_essential_tools

    install_kernel

    update_grub_configuration
	
}

main "$@"
echo "Edge node infrastructure setup completed successfully"
