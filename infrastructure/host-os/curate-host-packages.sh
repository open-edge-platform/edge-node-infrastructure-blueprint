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
	EXPECTED_FINGERPRINT="E6FA98203588250569758E97D176E3162086EE4C"
	wget -O /tmp/ptl.gpg https://download.01.org/intel-linux-overlay/ubuntu/E6FA98203588250569758E97D176E3162086EE4C.gpg
	ACTUAL_FINGERPRINT=$(gpg --show-keys --with-colons /tmp/ptl.gpg | awk -F: '/^fpr:/ {print $10}')

	# Compare fingerprints
	if [ "$ACTUAL_FINGERPRINT" = "$EXPECTED_FINGERPRINT" ]; then
        echo "Fingerprint matches! Safe to install."
        sudo cp /tmp/ptl.gpg /etc/apt/trusted.gpg.d/ptl.gpg
	else
		echo "ERROR: Fingerprint does not match! Aborting installation."
		echo "Expected: $EXPECTED_FINGERPRINT"
		echo "Actual:   $ACTUAL_FINGERPRINT"
		rm -f /tmp/ptl.gpg
		exit 1
	fi
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

install_gpu_npu_pkgs() {
    echo "Installing NPU,GPU Packages.."
    
    # Create installation directory
    INSTALL_DIR="/tmp/install_gpu_cpu"
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Downloading GPU drivers
    debpackage=(
		"https://github.com/intel/intel-graphics-compiler/releases/download/v2.28.4/intel-igc-core-2_2.28.4+20760_amd64.deb"
		"https://github.com/intel/intel-graphics-compiler/releases/download/v2.28.4/intel-igc-opencl-2_2.28.4+20760_amd64.deb"
		"https://github.com/intel/compute-runtime/releases/download/26.05.37020.3/intel-ocloc_26.05.37020.3-0_amd64.deb"
		"https://github.com/intel/compute-runtime/releases/download/26.05.37020.3/intel-opencl-icd_26.05.37020.3-0_amd64.deb"
		"https://github.com/intel/compute-runtime/releases/download/26.05.37020.3/libze-intel-gpu1_26.05.37020.3-0_amd64.deb"
		"https://github.com/oneapi-src/level-zero/releases/download/v1.22.4/level-zero_1.22.4+u24.04_amd64.deb"
		"https://github.com/oneapi-src/level-zero/releases/download/v1.22.4/level-zero-devel_1.22.4+u24.04_amd64.deb")
    
    # Download GPU packages 
    for url in "${debpackage[@]}"; do
		echo "Downloading: $url"
		filename=$(basename "$url")
		if wget "$url" -O "$filename"; then
			echo "Successfully downloaded: $filename"
		else
			echo "ERROR: Failed to download $filename"
			exit 1
		fi
	done
    
    # Downloading NPU drivers
    echo "Downloading NPU driver package..."
    npu_url="https://github.com/intel/linux-npu-driver/releases/download/v1.32.0/linux-npu-driver-v1.32.0.20260402-23905121947-ubuntu2404.tar.gz"
    npu_file="linux-npu-driver-v1.32.0.20260402-23905121947-ubuntu2404.tar.gz"
    
    if wget "$npu_url" -O "$npu_file"; then
		echo "Successfully downloaded NPU driver package"
		if tar -xf "$npu_file"; then
			echo "Successfully extracted NPU driver package"
		else
			echo "ERROR: Failed to extract NPU driver package"
			exit 1
		fi
	else
		echo "ERROR: Failed to download NPU driver package"
		exit 1
	fi
    
    # Verify all downloaded .deb files exist
    if ! ls ./*.deb 1> /dev/null 2>&1; then
		echo "ERROR: No .deb files found in $INSTALL_DIR"
		exit 1
	fi
    
    # Update package manager and install dependencies
    sudo apt update
    sudo apt install libtbb12 -y
    
    # Purge old packages if they exist
    sudo dpkg --purge --force-remove-reinstreq intel-driver-compiler-npu intel-fw-npu intel-level-zero-npu intel-level-zero-npu-dbgsym 2>/dev/null || true
    
    # Install all downloaded .deb packages with error checking
    echo "Installing downloaded packages..."
    if sudo dpkg -i ./*.deb; then
		echo "NPU,GPU Packages installed successfully"
	else
		echo "WARNING: Some packages failed to install, attempting to fix dependencies..."
		sudo apt --fix-broken install -y || {
			echo "ERROR: Failed to install packages"
			exit 1
		}
	fi
    
    # Cleanup: 
    rm -rf "$INSTALL_DIR"
    
    echo "Installation directory: $INSTALL_DIR"
   
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

	install_gpu_npu_pkgs

    install_kernel

    update_grub_configuration
	
}

main "$@"
echo "Edge node infrastructure setup completed successfully"
