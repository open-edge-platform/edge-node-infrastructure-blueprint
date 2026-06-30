#!/bin/bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

echo "http_proxy=${http_proxy:-}"
echo "https_proxy=${https_proxy:-}"

#======================================================
#  Edge Node Infrastructure Setup Script
#
# This script will set up the necessary environment 
# for edge node infrastructure development.
#======================================================


install_depended_packages() {
	echo "Updating apt and installing initial packages..."
	apt update
	apt upgrade -y
	apt install wget ethtool libbpf1 wayland-protocols -y
	echo "Initial packages installed."
}

create_ppa_sources_list() {
	echo "Creating Intel PTL PPA sources list..."
	mkdir -p /etc/apt/sources.list.d
	bash -c 'cat > /etc/apt/sources.list.d/intel-ptl.list << EOF
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
        cp /tmp/ptl.gpg /etc/apt/trusted.gpg.d/ptl.gpg
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
	apt update
	export DEBIAN_FRONTEND=noninteractive
	apt install -y --no-install-recommends libigfxcmrt-dev libigfxcmrt7 nano ocl-icd-libopencl1 curl openssh-server net-tools gir1.2-gst-plugins-bad-1.0 gir1.2-gst-plugins-base-1.0 gir1.2-gstreamer-1.0 gir1.2-gst-rtsp-server-1.0 gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-opencv gstreamer1.0-plugins-bad gstreamer1.0-plugins-bad-apps gstreamer1.0-plugins-base gstreamer1.0-plugins-base-apps gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly gstreamer1.0-pulseaudio gstreamer1.0-qt5 gstreamer1.0-rtsp gstreamer1.0-tools gstreamer1.0-x intel-media-va-driver-non-free libdrm-amdgpu1 libdrm-common libdrm-dev libdrm-intel1 libdrm-nouveau2 libdrm-radeon1 libdrm-tests libdrm2 libgstrtspserver-1.0-dev libgstrtspserver-1.0-0 libgstreamer-gl1.0-0 libgstreamer-opencv1.0-0 libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-bad1.0-dev libgstreamer-plugins-base1.0-0 libgstreamer-plugins-base1.0-dev libgstreamer1.0-0 libgstreamer1.0-dev libigdgmm-dev libigdgmm12 libmfx-gen1.2 libva-dev libva-drm2 libva-glx2 libva-wayland2 libva-x11-2 libva2 libwayland-bin libwayland-client0 libwayland-cursor0 libwayland-dev libwayland-doc libwayland-egl-backend-dev libwayland-egl1 libwayland-server0 linux-firmware mesa-utils mesa-vulkan-drivers libvpl-dev libvpl-tools libmfx-gen-dev onevpl-tools va-driver-all vainfo weston intel-gpu-tools libssl3 ffmpeg git-lfs lbzip2 openssl python3-pandas python3-pip python3-seaborn msr-tools powertop linuxptp lsscsi lsb-release vim chrony firmware-sof-signed iputils-ping tcpdump file less build-essential  rpm --allow-downgrades
	
	systemctl --root=/ disable systemd-timesyncd || true
	systemctl --root=/ mask    systemd-timesyncd || true
	systemctl --root=/ enable ssh || true
	systemctl --root=/ enable  chrony || true  
	echo "Essential tools and dependencies installed."
}

enable_display_manager() {
	echo "Enabling display manager for desktop environment..."
	apt install -y gdm3 || apt install -y lightdm
	systemctl --root=/ enable gdm3 2>/dev/null || systemctl --root=/ enable lightdmG
	echo "Display manager enabled."
}

install_cloud_init() {
	echo "Installing and configuring cloud-init"
	export DEBIAN_FRONTEND=noninteractive

	apt update
	apt install -y cloud-init

	echo "Configuring cloud-init for local-only operation..."

	# Remove any previous custom configs
	rm -f /etc/cloud/cloud.cfg.d/99-*.cfg

	# Use only the None datasource
	cat >/etc/cloud/cloud.cfg.d/99-datasource.cfg <<'EOF'
datasource_list: [ None ]
EOF

	# Local cloud-init configuration
	cat >/etc/cloud/cloud.cfg.d/99-local.cfg <<'EOF'
#cloud-config

preserve_hostname: true
manage_etc_hosts: true
system_upgrade: false

runcmd:
  - echo "Cloud-init provisioning completed" > /var/log/cloud-init-local.log
final_message: 'Cloud-init local configuration completed at $TIMESTAMP'
EOF

	# ds-identify configuration
	cat >/etc/cloud/ds-identify.cfg <<'EOF'
policy: enabled
EOF

	echo "Enabling cloud-init services..."

	systemctl --root=/ enable cloud-init-local.service || true
	systemctl --root=/ enable cloud-init.service || true
	systemctl --root=/ enable cloud-config.service || true
	systemctl --root=/ enable cloud-final.service || true

	echo "Cleaning cloud-init state..."

	cloud-init clean --logs || true
	echo "policy: enabled" > /etc/cloud/ds-identify.cfg
	echo "datasource: NoCloud" >> /etc/cloud/ds-identify.cfg
	rm -rf /var/lib/cloud/*

	echo "Cloud-init installation complete."

}

install_docker() {
	echo "Installing Docker..."
	apt update
	apt install -y ca-certificates curl gnupg

	install -m 0755 -d /etc/apt/keyrings

	curl -fsSL --connect-timeout 10 --max-time 60 https://download.docker.com/linux/ubuntu/gpg \
		| gpg --dearmor -o /etc/apt/keyrings/docker.gpg

	chmod a+r /etc/apt/keyrings/docker.gpg

	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
		$(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
		tee /etc/apt/sources.list.d/docker.list > /dev/null
	apt update
	apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

	systemctl --root=/ enable docker || true
	echo "Docker installed and running."
}	
instal_k3s() {
	echo "Installing k3s..."
	for i in 1 2 3; do
		curl -sfL --max-time 120 --retry 3 \
			https://get.k3s.io -o /tmp/k3s-install.sh && break
		echo "  k3s download attempt $i failed, retrying..."
		sleep 10
	done

	chmod +x /tmp/k3s-install.sh

	INSTALL_K3S_EXEC="server --disable=traefik" \
		INSTALL_K3S_SKIP_ENABLE=true \
		INSTALL_K3S_SKIP_START=true \
		sh /tmp/k3s-install.sh

	systemctl --root=/ enable k3s || true
	
	echo "k3s installed successfully."
}
install_helm() {
	echo "Installing Helm..."
	curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
	rm get_helm.sh
	echo "Helm installed successfully."
}

install_realsense_pkgs(){
	echo "Installing Intel RealSense packages..."
	# ref: https://docs.ros.org/en/iron/p/librealsense2/user_docs/distribution_linux.html
	mkdir -p /etc/apt/keyrings
	KEY_ID=$(curl -sSf "https://librealsense.intel.com/Debian/apt-repo/dists/$(lsb_release -cs)/InRelease" \
		| gpg --status-fd 1 --verify 2>/dev/null | grep "NO_PUBKEY" | awk '{print $3}')
	curl -sSf "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${KEY_ID}" \
		| gpg --dearmor | tee /etc/apt/keyrings/librealsense.gpg > /dev/null
	chmod 644 /etc/apt/keyrings/librealsense.gpg
	echo "deb [signed-by=/etc/apt/keyrings/librealsense.gpg] https://librealsense.intel.com/Debian/apt-repo $(lsb_release -cs) main" \
		| tee /etc/apt/sources.list.d/librealsense.list
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y \
		librealsense2-dkms librealsense2 librealsense2-utils librealsense2-dev librealsense2-gl

	echo "Intel RealSense packages installed successfully."
}
install_performance_tools() {
	echo "Installing performance analysis tools..."
	wget -nv -r -l1 -nd -A deb -P /tmp https://download.01.org/intel-linux-overlay/ubuntu/linux-tools/
	if [ $? -eq 0 ]; then
		echo "Successfully downloaded the debian files"
		apt install -y  -f --fix-broken -o Dpkg::Options::="--force-overwrite" /tmp/*.deb
		apt install -f
	else
		echo "Failure to download the debian files"
	fi
	echo "Performance analysis tools installed successfully."
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
    apt update
    apt install libtbb12 -y
    
    # Purge old packages if they exist
    dpkg --purge --force-remove-reinstreq intel-driver-compiler-npu intel-fw-npu intel-level-zero-npu intel-level-zero-npu-dbgsym 2>/dev/null || true
    
    # Install all downloaded .deb packages with error checking
    echo "Installing downloaded packages..."
    if dpkg -i ./*.deb; then
		echo "NPU,GPU Packages installed successfully"
	else
		echo "WARNING: Some packages failed to install, attempting to fix dependencies..."
		apt --fix-broken install -y || {
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
	apt install linux-image-6.18-intel linux-headers-6.18-intel -y
	KERNEL_VERSION=$(find /lib/modules/ -maxdepth 1 -name '*intel*' -type d | head -n 1 | xargs basename)
	if [ -z "$KERNEL_VERSION" ]; then
    	echo "ERROR: No Intel kernel found in /lib/modules!"
    		exit 1
	fi
	echo "Found Kernel Version: $KERNEL_VERSION"

	echo "=== Step 4: Generating Initramfs Ramdisk ==="
	update-initramfs -c -k "$KERNEL_VERSION"

	echo "=== Step 5: Creating Generic Boot Symlinks ==="
	ln -sf "vmlinuz-$KERNEL_VERSION" /boot/vmlinuz-intel
	ln -sf "initrd.img-$KERNEL_VERSION" /boot/initrd.img-intel
	echo "Linux kernel installed."
}

main() {

    install_depended_packages

    create_ppa_sources_list

    download_and_install_gpg_key

    set_preferred_package_list

    install_essential_tools

	enable_display_manager


	install_cloud_init

	install_docker

	instal_k3s

	install_helm

	install_realsense_pkgs

    install_gpu_npu_pkgs

    install_kernel

	install_performance_tools
}

main "$@"
echo "Edge node infrastructure setup completed successfully"
