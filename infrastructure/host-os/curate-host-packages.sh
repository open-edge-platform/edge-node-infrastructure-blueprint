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
	apt install -y \
		systemd systemd-resolved udev initramfs-tools bsdutils gzip util-linux util-linux-extra \
		linux-base grub2-common grub-pc-bin grub-efi-amd64 grub-efi-amd64-bin grub-efi-amd64-signed efibootmgr shim-signed \
		ubuntu-minimal ubuntu-standard ubuntu-desktop-minimal \
		language-pack-en language-pack-en-base language-pack-gnome-en language-pack-gnome-en-base \
		linux-firmware firmware-sof-signed wireless-regdb \
		openssl libssl-dev \
		build-essential cmake make git git-lfs apt-transport-https gnupg lsb-release rsync \
		python3-pip python3-netifaces libpython3.12t64 \
		libattr1 libconfig9 libnuma1 libslang2 libdw1t64 \
		libdrm2 libdrm-common libdrm-dev libdrm-intel1 libdrm-radeon1 libdrm-amdgpu1 libdrm-nouveau2 \
		mesa-vulkan-drivers mesa-utils intel-media-va-driver-non-free libigfxcmrt7 libigdgmm12 ocl-icd-libopencl1 \
		libva2 libva-drm2 libva-dev libva-glx2 libva-wayland2 libva-x11-2 libvpl2 libmfx-gen1.2 vainfo \
		ffmpeg libavcodec62 libavformat62 libavutil60 libavdevice62 libavfilter11 libswresample6 libswscale9 \
		libwayland-bin libwayland-client0 libwayland-cursor0 libwayland-dev libwayland-doc libwayland-egl-backend-dev \
		libwayland-egl1 libwayland-server0 weston libweston-10-0 \
		xserver-xorg-core libglew-dev libglm-dev libsdl2-dev \
		gir1.2-gst-plugins-bad-1.0 gir1.2-gstreamer-1.0 gstreamer1.0-plugins-bad gstreamer1.0-plugins-good \
		gstreamer1.0-plugins-base gstreamer1.0-pulseaudio libgstreamer1.0-0 libgstreamer-gl1.0-0 \
		libgstreamer-plugins-base1.0-0 libgstreamer-plugins-bad1.0-0 va-driver-all \
		libxdp1 libxdp-dev xdp-tools \
		libnl-3-200 libnl-genl-3-200 iproute2 net-tools iputils-ping tcpdump curl linuxptp dnsmasq-base network-manager \
		bluez \
		libtpms0 libtpms-dev \
		intel-gpu-tools thermald rpc-go pcm lms metee stress-ng \
		pahole libbabeltrace1 libdebuginfod1t64 libopencsd1 libtracefs1 libtraceevent1 libpci3 pciutils \
		vim nano mc less file mawk grep diffutils findutils debianutils ncurses-base ncurses-bin cron msr-tools i2c-tools \
		lsscsi sg3-utils dosfstools gdisk pigz rpm \
		openssh-server chrony mosquitto mosquitto-clients socat dbus-x11 docker-compose efivar efibootmgr
	
	systemctl --root=/ disable systemd-timesyncd || true
	systemctl --root=/ mask    systemd-timesyncd || true
	systemctl --root=/ enable ssh || true
	systemctl --root=/ enable  chrony || true  
	echo "Essential tools and dependencies installed."
}

# The latest intel-lpmd version 0.1.0 .deb package targets Ubuntu 25.10 and cannot
# be installed on Noble due to unmet dependencies (requires libnl ≥ 3.11, libxml2-16,
# and glibc ≥ 2.42, whereas Noble only provides 3.7.0 / libxml2.so.2 / 2.39)

build_install_lpmd () {
	# Install dependencies to build intel-lpmd
	apt install -y autoconf autoconf-archive gcc libglib2.0-dev libdbus-1-dev libxml2-dev libnl-3-dev \
	         libnl-genl-3-dev libsystemd-dev gtk-doc-tools libupower-glib-dev automake
	cd /tmp
	git clone --branch v0.1.0 https://github.com/intel/intel-lpmd.git lpmd
	cd lpmd
	./autogen.sh
	make
	sudo make install
	# cleanup install dependencies
	apt remove -y autoconf autoconf-archive gcc libglib2.0-dev libdbus-1-dev libxml2-dev libnl-3-dev \
		libnl-genl-3-dev libsystemd-dev gtk-doc-tools libupower-glib-dev automake
	apt autoremove -y
	apt clean
	# Enable service
	systemctl --root=/ enable intel_lpmd.service
	echo "Installed intel-lpmd"
}

enable_display_manager() {
	echo "Enabling display manager for desktop environment..."
	apt install -y gdm3 || apt install -y lightdm
	systemctl --root=/ enable gdm3 2>/dev/null || systemctl --root=/ enable lightdmG
	echo "Display manager enabled."
}

setup_firefox() {
	echo "Setting up Firefox..."
	add-apt-repository ppa:mozillateam/ppa
	echo '
Package: firefox*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
' | sudo tee /etc/apt/preferences.d/mozilla-firefox

	apt update
	apt install -y firefox
	echo "Firefox setup complete."
}

audio_fw_update() {
	echo "Updating audio firmware and codec configuration..."

	local sof_dir="/lib/firmware/intel/sof-ipc4/ptl"
	local tplg_dir="/lib/firmware/intel/sof-ipc4-tplg"
	local codec_type="${AUDIO_CODEC_TYPE:-soundwire}"
	local topology_file="${AUDIO_TOPOLOGY_FILE:-}"
	local strict_topology_check="${AUDIO_TOPOLOGY_REQUIRED:-false}"
	local candidate

	# Disable legacy HD audio kernel modules.
	cat > /etc/modprobe.d/blacklist_hda.conf <<'EOF'
blacklist snd_hda_intel
blacklist snd_hda_core
EOF

	# Restrict ALSA stack to SOF/I2S path.
	cat > /etc/modprobe.d/alsa.conf <<'EOF'
options snd_sof_intel_hda_common sof_use_tplg_nhlt=1
options snd_intel_dspcfg dsp_driver=3
EOF

	# Download PTL SOF firmware binaries.
	mkdir -p "$sof_dir"
	wget -O "$sof_dir/sof-ptl-openmodules.ri" \
		https://raw.githubusercontent.com/thesofproject/sof-bin/main/v2.13.x/sof-ipc4-v2.13/ptl/intel-signed/sof-ptl-openmodules.ri
	sleep 3
	wget -O "$sof_dir/sof-ptl.ri" \
		https://raw.githubusercontent.com/thesofproject/sof-bin/main/v2.13.x/sof-ipc4-v2.13/ptl/intel-signed/sof-ptl.ri
	sleep 3

	# Select topology by codec type.
	# override automatic selection by setting AUDIO_TOPOLOGY_FILE.
	if [ -z "$topology_file" ]; then
		case "$codec_type" in
			soundwire|alc722-cg)
				# Common PTL SoundWire topology candidates.
				for candidate in \
					"sof-ptl-rt722.tplg" \
					"sof-ptl-rt722-sdca.tplg" \
					"sof-ptl-max98373-rt5682.tplg"; do
					if [ -f "$tplg_dir/$candidate" ]; then
						topology_file="$candidate"
						break
					fi
				done

				# Fallback: any PTL SoundWire-like topology name.
				if [ -z "$topology_file" ]; then
					for candidate in "$tplg_dir"/*ptl*rt7*.tplg "$tplg_dir"/*ptl*sdw*.tplg "$tplg_dir"/*ptl*.tplg; do
						if [ -f "$candidate" ]; then
							topology_file="$(basename "$candidate")"
							break
						fi
					done
				fi
				;;
			hda-dsp|hda)
				# Common PTL HDA-over-DSP topology candidates.
				for candidate in \
					"sof-hda-generic-2ch.tplg" \
					"sof-hda-generic.tplg"; do
					if [ -f "$tplg_dir/$candidate" ]; then
						topology_file="$candidate"
						break
					fi
				done

				# Fallback: any HDA topology name.
				if [ -z "$topology_file" ]; then
					for candidate in "$tplg_dir"/*hda*.tplg "$tplg_dir"/*ptl*.tplg; do
						if [ -f "$candidate" ]; then
							topology_file="$(basename "$candidate")"
							break
						fi
					done
				fi
				;;
			*)
				echo "ERROR: Unsupported AUDIO_CODEC_TYPE='$codec_type'. Use soundwire or hda-dsp."
				return 1
				;;
		esac
	fi

	if [ -n "$topology_file" ] && [ -f "$tplg_dir/$topology_file" ]; then
		ln -sf "$tplg_dir/$topology_file" /lib/firmware/intel/sof-ipc4/sof-ptl.tplg
		echo "Selected audio topology: $topology_file"
		echo "Audio firmware update complete."
		return 0
	fi

	echo "WARNING: Could not resolve topology file under $tplg_dir."
	echo "WARNING: Set AUDIO_TOPOLOGY_FILE to an existing .tplg file if audio routing is required."
	ls -1 "$tplg_dir"/*.tplg 2>/dev/null || true

	if [ "$strict_topology_check" = "true" ]; then
		echo "ERROR: AUDIO_TOPOLOGY_REQUIRED=true and no valid topology file was found."
		return 1
	fi

	echo "Continuing without creating /lib/firmware/intel/sof-ipc4/sof-ptl.tplg symlink."
	echo "Audio firmware update complete."
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

	# shellcheck source=/dev/null
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
		$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
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

# Install latest helm version v4.2.4
# Git commit of the installer script
COMMIT_HASH="3900f434fd3ef2b84065dc04508df48f288dba00"
SCRIPT_URL="https://raw.githubusercontent.com/helm/helm/${COMMIT_HASH}/scripts/get-helm-3"
# Matching SHA-256 hash for that exact commit
EXPECTED_HASH="38b65f882d9cae3891755bdb03becc6a01ae6f9cb24826c191f219ddfee70a5d"

install_helm() {
	echo "Installing Helm..."
	if ! curl -fsSL -o get_helm.sh "$SCRIPT_URL"; then
		echo "Failed to download Helm installer." >&2
		rm -f get_helm.sh
		return 1
	fi
	ACTUAL_HASH=$(sha256sum get_helm.sh | awk '{print $1}')
	if [[ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]]; then
		echo "Helm installer checksum verification failed." >&2
		rm -f get_helm.sh
		return 1
	fi
	chmod 700 get_helm.sh
	./get_helm.sh
	rm -f get_helm.sh
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
	if wget -nv -r -l1 -nd -A deb -P /tmp https://download.01.org/intel-linux-overlay/ubuntu/linux-tools/; then
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
}

main() {

	install_depended_packages

	create_ppa_sources_list

	download_and_install_gpg_key

	set_preferred_package_list

	install_essential_tools

	build_install_lpmd

	enable_display_manager

	setup_firefox

	audio_fw_update

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
