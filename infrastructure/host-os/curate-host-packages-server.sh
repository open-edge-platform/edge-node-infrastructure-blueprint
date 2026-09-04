#!/bin/bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

echo "http_proxy=${http_proxy:-}"
echo "https_proxy=${https_proxy:-}"

INTEL_OVERLAY_URL="https://download.01.org/edge-linux-overlay/ubuntu"
INTEL_OVERLAY_KEY_URL="https://download.01.org/edge-linux-overlay/ubuntu/9C63745D2A211728B8CE98C5F84B1B6A704E41B2.gpg"
INTEL_OVERLAY_KEY_FINGERPRINT="9C63745D2A211728B8CE98C5F84B1B6A704E41B2"
SOF_OPENMODULES_SHA256="0bc5c1942918e86f84b9a7e97efb7e82b9aad2891398927780d5afd433128f3f"
SOF_FIRMWARE_SHA256="ace80f314159034a2372c229a2a45443499649f6e747a63c7f2644464d399eba"
SOF_RT722_TOPOLOGY_SHA256="fedb1f01b91b14335cca4bc5d89992f224687e633455ca7c6f0b5c00fc9cac2d"
SOF_HDA_TOPOLOGY_SHA256="d2a6128569c980c39ecc48ab81ce253a9a3160f46e9ba843d7b056293388ee24"
INTEL_OVERLAY_COMPONENTS="main non-free multimedia kernels"
INTEL_ECI_URL="https://eci.intel.com/repos/noble"
INTEL_ECI_KEY_URL="https://eci.intel.com/repos/gpg-keys/GPG-PUB-KEY-INTEL-ECI.gpg"
INTEL_ECI_KEY_FINGERPRINT="B1CDAB5E8EE9205CBD8A7500EF16D1B6C97E2FC9"
INTEL_OPENVINO_URL="https://apt.repos.intel.com/openvino/2025"
INTEL_ONEAPI_URL="https://apt.repos.intel.com/oneapi"
INTEL_SW_PRODUCTS_KEY_URL="https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB"
INTEL_SW_PRODUCTS_KEY_FINGERPRINT="BF4385F91CA5FC005AB39E1C1A8497B11911E097"
MOZILLA_PPA_KEY_FINGERPRINT="0AB215679C571D1C8325275B9BDB3D89CE49EC21"


#======================================================
#  Edge Node Infrastructure Setup Script (SERVER/HEADLESS)
#
# This script will set up the necessary environment
# for edge node infrastructure development on a headless
# server image: no display manager, no Firefox.
#
# Server counterpart of curate-host-packages.sh (desktop).
# Keep the two in sync when updating driver/kernel versions.
#
# Aligned with: generic-handheld-os-server-template.yml
#======================================================


install_depended_packages() {
	echo "Updating apt and installing initial packages..."
	apt update
	apt upgrade -y
	apt install -y --no-install-recommends wget ethtool libbpf1 wayland-protocols binutils
	echo "Initial packages installed."
}

download_file() {
	local url="$1"
	local out_file="$2"
	curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 120 "${url}" -o "${out_file}"
}

download_and_verify_sha256() {
	local url="$1"
	local out_file="$2"
	local expected_sha256="$3"
	local temp_file="${out_file}.tmp"

	rm -f "${temp_file}"
	download_file "${url}" "${temp_file}"
	if ! printf '%s  %s\n' "${expected_sha256}" "${temp_file}" | sha256sum -c -; then
		echo "ERROR: SHA-256 verification failed for ${out_file}" >&2
		rm -f "${temp_file}"
		return 1
	fi
	mv -f "${temp_file}" "${out_file}"
}

verify_gpg_fingerprint() {
	local key_file="$1"
	local expected_fingerprint="$2"
	local actual_fingerprint

	actual_fingerprint=$(gpg --show-keys --with-colons "${key_file}" | awk -F: '/^fpr:/ {print $10; exit}')
	if [ "${actual_fingerprint}" != "${expected_fingerprint}" ]; then
		echo "ERROR: GPG key fingerprint mismatch for ${key_file}." >&2
		echo "Expected: ${expected_fingerprint}" >&2
		echo "Actual:   ${actual_fingerprint}" >&2
		return 1
	fi
}

verify_gpg_key_id() {
	local key_file="$1"
	local expected_key_id="$2"
	local actual_fingerprint

	actual_fingerprint=$(gpg --show-keys --with-colons "${key_file}" | awk -F: '/^fpr:/ {print $10; exit}')
	if [[ "${actual_fingerprint,,}" != *"${expected_key_id,,}" ]]; then
		echo "ERROR: GPG key ID mismatch for ${key_file}." >&2
		echo "Expected key ID: ${expected_key_id}" >&2
		echo "Actual fingerprint: ${actual_fingerprint}" >&2
		return 1
	fi
}

create_ppa_sources_list() {
	local SNAPSHOT_NAME="2026_S_REL3-meta-data-fix"
	echo "Creating Intel overlay repository sources list from snapshot ${SNAPSHOT_NAME}..."
	mkdir -p /etc/apt/sources.list.d
	cat > /etc/apt/sources.list.d/intel-overlay.list << EOF
deb [signed-by=/etc/apt/keyrings/intel-overlay.gpg] ${INTEL_OVERLAY_URL} noble/snapshots/${SNAPSHOT_NAME} ${INTEL_OVERLAY_COMPONENTS}
EOF
	echo "Intel overlay repository sources list created."
}

download_and_install_gpg_key() {
	echo "Downloading and installing Intel overlay GPG key..."
	install -d -m 0755 /etc/apt/keyrings
	tmp_key_file="/tmp/intel-overlay-public.gpg"
	download_file "${INTEL_OVERLAY_KEY_URL}" "${tmp_key_file}"

	local actual_fingerprint
	actual_fingerprint=$(gpg --show-keys --with-colons "${tmp_key_file}" | awk -F: '/^fpr:/ {print $10; exit}')
	if [ "${actual_fingerprint}" != "${INTEL_OVERLAY_KEY_FINGERPRINT}" ]; then
		echo "ERROR: Intel overlay GPG key fingerprint mismatch! Aborting."
		echo "Expected: ${INTEL_OVERLAY_KEY_FINGERPRINT}"
		echo "Actual:   ${actual_fingerprint}"
		rm -f "${tmp_key_file}"
		return 1
	fi
	echo "Intel overlay GPG key fingerprint verified."

	gpg --dearmor -o /etc/apt/keyrings/intel-overlay.gpg "${tmp_key_file}"
	rm -f "${tmp_key_file}"
	chmod 0644 /etc/apt/keyrings/intel-overlay.gpg
	echo "Intel overlay GPG key installed."
}

create_eci_sources_list() {
	echo "Creating Intel ECI repository sources list..."
	mkdir -p /etc/apt/sources.list.d
	cat > /etc/apt/sources.list.d/intel-eci.list << EOF
deb [signed-by=/etc/apt/keyrings/intel-eci.gpg] ${INTEL_ECI_URL} isar main
EOF
	echo "Intel ECI repository sources list created."
}

download_and_install_eci_gpg_key() {
	echo "Downloading and installing Intel ECI GPG key..."
	install -d -m 0755 /etc/apt/keyrings
	tmp_key_file="/tmp/intel-eci-public.gpg"
	download_file "${INTEL_ECI_KEY_URL}" "${tmp_key_file}"
	verify_gpg_fingerprint "${tmp_key_file}" "${INTEL_ECI_KEY_FINGERPRINT}"
	gpg --dearmor -o /etc/apt/keyrings/intel-eci.gpg "${tmp_key_file}"
	rm -f "${tmp_key_file}"
	chmod 0644 /etc/apt/keyrings/intel-eci.gpg
	echo "Intel ECI GPG key installed."
}

create_openvino_oneapi_sources() {
	echo "Creating OpenVINO and oneAPI repository sources..."
	install -d -m 0755 /etc/apt/keyrings

	# Download Intel SW Products GPG key (shared by OpenVINO and oneAPI)
	tmp_key_file="/tmp/intel-sw-products.pub"
	download_file "${INTEL_SW_PRODUCTS_KEY_URL}" "${tmp_key_file}"
	verify_gpg_fingerprint "${tmp_key_file}" "${INTEL_SW_PRODUCTS_KEY_FINGERPRINT}"
	gpg --dearmor -o /etc/apt/keyrings/intel-sw-products.gpg "${tmp_key_file}"
	rm -f "${tmp_key_file}"
	chmod 0644 /etc/apt/keyrings/intel-sw-products.gpg

	# OpenVINO 2025
	cat > /etc/apt/sources.list.d/intel-openvino.list << EOF
deb [signed-by=/etc/apt/keyrings/intel-sw-products.gpg] ${INTEL_OPENVINO_URL} ubuntu24 main
EOF

	# oneAPI (oneDNN / Base Toolkit)
	cat > /etc/apt/sources.list.d/intel-oneapi.list << EOF
deb [signed-by=/etc/apt/keyrings/intel-sw-products.gpg] ${INTEL_ONEAPI_URL} all main
EOF

	echo "OpenVINO and oneAPI repository sources created."
}

create_mozilla_ppa_sources() {
	echo "Creating Mozilla Team PPA sources list..."
	install -d -m 0755 /etc/apt/keyrings

	# Download Mozilla Team PPA GPG key
	tmp_key_file="/tmp/mozillateam-ppa.gpg"
	download_file \
		"https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x0AB215679C571D1C8325275B9BDB3D89CE49EC21" \
		"${tmp_key_file}"
	verify_gpg_fingerprint "${tmp_key_file}" "${MOZILLA_PPA_KEY_FINGERPRINT}"
	local actual_fingerprint
	actual_fingerprint=$(gpg --show-keys --with-colons "${tmp_key_file}" | awk -F: '/^fpr:/ {print $10; exit}')
	if [ "${actual_fingerprint}" != "${MOZILLA_PPA_KEY_FINGERPRINT}" ]; then
		echo "ERROR: Mozilla PPA GPG key fingerprint mismatch! Aborting."
		echo "Expected: ${MOZILLA_PPA_KEY_FINGERPRINT}"
		echo "Actual:   ${actual_fingerprint}"
		rm -f "${tmp_key_file}"
		return 1
	fi
	echo "Mozilla PPA GPG key fingerprint verified."

	gpg --dearmor -o /etc/apt/keyrings/mozillateam-ppa.gpg "${tmp_key_file}"
	rm -f "${tmp_key_file}"
	chmod 0644 /etc/apt/keyrings/mozillateam-ppa.gpg

	# Mozilla Team PPA (Firefox .deb, avoids Ubuntu's snap-transitional package)
	cat > /etc/apt/sources.list.d/mozillateam-ppa.list << EOF
deb [signed-by=/etc/apt/keyrings/mozillateam-ppa.gpg] https://ppa.launchpadcontent.net/mozillateam/ppa/ubuntu noble main
EOF

	# Pin Mozilla PPA at priority 1001 (higher than archive, ensures .deb Firefox over snap)
	cat > /etc/apt/preferences.d/mozilla-ppa << EOF
Package: *
Pin: origin ppa.launchpadcontent.net
Pin-Priority: 1001
EOF

	echo "Mozilla Team PPA sources list created."
}


set_preferred_package_list() {
	echo "Setting preferred package list..."

	# Intel overlay: priority 2000 (highest — matches template)
	cat > /etc/apt/preferences.d/intel-overlay << EOF
Package: *
Pin: origin download.01.org
Pin-Priority: 2000
EOF

	# Intel ECI repo: priority 600 (provides ethtool, systemd, v4l-utils, udev with eci patches)
	cat > /etc/apt/preferences.d/intel-eci << EOF
Package: *
Pin: origin eci.intel.com
Pin-Priority: 600
EOF
}


install_essential_tools() {
	echo "Installing essential tools and dependencies..."
	apt update
	export DEBIAN_FRONTEND=noninteractive
	echo "=== DEBUG_BUILD: Checking package policies ===" # DEBUG_BUILD
	apt-cache policy intel-media-va-driver intel-media-va-driver-non-free mesa-libgallium 2>/dev/null || true # DEBUG_BUILD
	echo "=== END DEBUG_BUILD ===" # DEBUG_BUILD
	apt install -y --allow-downgrades --no-install-recommends \
		alsa-topology-conf \
		alsa-ucm-conf \
		alsa-utils \
		apparmor \
		at \
		v4l-utils \
		avahi-daemon \
		avahi-utils \
		bc \
		bluez \
		bridge-utils \
		build-essential \
		ca-certificates \
		chrony \
		clinfo \
		cloud-init \
		cmake \
		conntrack \
		cpu-checker \
		cron \
		curl \
		dbus \
		dkms \
		dnsmasq-base \
		dns-root-data \
		dnsutils \
		dosfstools \
		e2fsprogs \
		ethtool \
		ffmpeg \
		file \
		fio \
		firmware-sof-signed \
		gdisk \
		gir1.2-gst-plugins-bad-1.0 \
		gir1.2-gstreamer-1.0 \
		git \
		git-lfs \
		gnupg \
		gstreamer1.0-icamera \
		gstreamer1.0-libcamera \
		gstreamer1.0-plugins-bad \
		gstreamer1.0-plugins-base \
		gstreamer1.0-plugins-good \
		gstreamer1.0-pulseaudio \
		gstreamer1.0-tools \
		htop \
		hwdata \
		i2c-tools \
		intel-gpu-tools \
		intel-media-va-driver-non-free \
		intel-microcode \
		intel-opencl-icd \
		iproute2 \
		iptables \
		iputils-ping \
		iucode-tool \
		jq \
		libattr1 \
		libasound2t64 \
		libatopology2t64 \
		libavahi-client3 \
		libavahi-common-data \
		libavahi-common3 \
		libavahi-core7 \
		libavahi-glib1 \
		libavcodec62 \
		libavdevice62 \
		libavfilter11 \
		libavformat62 \
		libavutil60 \
		libbluetooth3 \
		libcamera-tools \
		libcamhal-common \
		libcamhal-ipu75xa \
		libcamhal-ipu75xa0 \
		libcamhal0 \
		grub-pc-bin \
		libdebuginfod1t64 \
		libdrm-amdgpu1 \
		libdrm-common \
		libdrm-dev \
		libdrm-intel1 \
		libdrm-nouveau2 \
		libdrm-radeon1 \
		libdrm2 \
		libfftw3-single3 \
		libglew-dev \
		libglm-dev \
		libgstreamer-plugins-bad1.0-0 \
		libgstreamer-plugins-base1.0-0 \
		libgstreamer1.0-0 \
		libgstreamer1.0-dev \
		libgstreamer-gl1.0-0 \
		libgsticamerainterface-1.0-1 \
		libigdgmm12 \
		libigfxcmrt7 \
		libip4tc2 \
		libllvm18 \
		libmfx-gen1.2 \
		libmnl0 \
		libnfnetlink0 \
		libnftnl11 \
		libnss-mdns \
		libsamplerate0 \
		libsdl2-dev \
		libseccomp2 \
		libsndfile1 \
		libswresample6 \
		libswscale9 \
		libsystemd0 \
		libtpms-dev \
		libtpms0 \
		libva2 \
		libva-dev \
		libva-drm2 \
		libva-glx2 \
		libva-wayland2 \
		libva-x11-2 \
		libvirt-sanlock \
		libvpl2 \
		libwayland-bin \
		libwayland-client0 \
		libwayland-cursor0 \
		libwayland-dev \
		libwayland-doc \
		libwayland-egl1 \
		libwayland-egl-backend-dev \
		libwayland-server0 \
		libxdp-dev \
		libxdp1 \
		libxtables12 \
		libc6 \
		linux-bpf-dev \
		linux-firmware \
		linux-intel-bpftool \
		linux-intel-cpupower \
		linux-intel-misc-tools \
		linux-intel-perf \
		linux-intel-rtla \
		linux-intel-usbip \
		linuxptp \
		lms \
		lm-sensors \
		logrotate \
		lsb-release \
		lsof \
		lsscsi \
		lvm2 \
		lzop \
		make \
		manpages \
		manpages-dev \
		mc \
		mdadm \
		mesa-utils \
		mesa-vulkan-drivers \
		metee \
		mosquitto \
		mosquitto-clients \
		msr-tools \
		nano \
		net-tools \
		networkd-dispatcher \
		nftables \
		ocl-icd-libopencl1 \
		open-iscsi \
		openssl \
		parted \
		patch \
		pciutils \
		pigz \
		pkg-config \
		polkitd \
		psmisc \
		python3-cpuinfo \
		python3-dev \
		python3-netifaces \
		python3-odf \
		python3-openpyxl \
		python3-pip \
		python3-rich \
		python3-systemd \
		python3-tables \
		read-edid \
		rfkill \
		rpc-go \
		rpm \
		rsync \
		rsyslog \
		screen \
		sg3-utils \
		snapd \
		socat \
		software-properties-common \
		stress-ng \
		sudo \
		sysbench \
		thermald \
		thin-provisioning-tools \
		tmux \
		tcpdump \
		ufw \
		unattended-upgrades \
		unzip \
		upower \
		usb-modeswitch \
		util-linux-extra \
		va-driver-all \
		vainfo \
		vim \
		wayland-protocols \
		wireless-regdb \
		xdp-tools \
		xfsprogs \
		xxd \
		zstd 
	

	systemctl --root=/ disable systemd-timesyncd || true
	systemctl --root=/ mask    systemd-timesyncd || true
	systemctl --root=/ enable ssh || true
	systemctl --root=/ enable  chrony || true
    echo "Installing pcm"
	cd /tmp
	git clone -b 202604 --recursive https://github.com/intel/pcm.git
	cd pcm
	mkdir build
	cd build
	cmake ..
	make -j"$(nproc)"
	sudo cp -r bin/* /usr/local/bin/
	echo 'msr' | sudo tee /etc/modules-load.d/intel-pcm.conf > /dev/null
	cd /
	rm -rf /tmp/pcm
	echo "Essential tools and dependencies installed."
}



audio_fw_update() {
	echo "Updating audio firmware and codec configuration..."

	local sof_dir="/lib/firmware/intel/sof-ipc4/ptl"
	local tplg_dir="/lib/firmware/intel/sof-ace-tplg"
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

	# Download Panther Lake SOF firmware binaries.
	mkdir -p "$sof_dir"
	download_and_verify_sha256 \
		"https://raw.githubusercontent.com/thesofproject/sof-bin/main/v2.13.x/sof-ipc4-v2.13/ptl/intel-signed/sof-ptl-openmodules.ri" \
		"$sof_dir/sof-ptl-openmodules.ri" "${SOF_OPENMODULES_SHA256}"
	sleep 3
	download_and_verify_sha256 \
		"https://raw.githubusercontent.com/thesofproject/sof-bin/main/v2.13.x/sof-ipc4-v2.13/ptl/intel-signed/sof-ptl.ri" \
		"$sof_dir/sof-ptl.ri" "${SOF_FIRMWARE_SHA256}"
	sleep 3

	# Download topology files to sof-ace-tplg (aligned with template paths)
	mkdir -p "$tplg_dir"
	# SoundWire codec (ALC722-CG / rt722)
	download_and_verify_sha256 \
		"https://raw.githubusercontent.com/thesofproject/sof-bin/main/v2.13.x/sof-ipc4-tplg-v2.13/sof-ptl-rt722.tplg" \
		"$tplg_dir/sof-ptl-rt722.tplg" "${SOF_RT722_TOPOLOGY_SHA256}"
	# HD audio codec via DSP
	download_and_verify_sha256 \
		"https://raw.githubusercontent.com/thesofproject/sof-bin/main/v2.13.x/sof-ipc4-tplg-v2.13/sof-hda-generic.tplg" \
		"$tplg_dir/sof-hda-generic.tplg" "${SOF_HDA_TOPOLOGY_SHA256}"

	# Select topology by codec type.
	# override automatic selection by setting AUDIO_TOPOLOGY_FILE.
	if [ -z "$topology_file" ]; then
		case "$codec_type" in
			soundwire|alc722-cg)
				# Common Panther Lake SoundWire topology candidates.
				for candidate in \
					"sof-ptl-rt722.tplg" \
					"sof-ptl-rt722-sdca.tplg" \
					"sof-ptl-max98373-rt5682.tplg"; do
					if [ -f "$tplg_dir/$candidate" ]; then
						topology_file="$candidate"
						break
					fi
				done

				# Fallback: any Panther Lake SoundWire-like topology name.
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
				# Common Panther Lake HDA-over-DSP topology candidates.
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

	# Use only NoCloud and None datasources (aligned with template)
	cat >/etc/cloud/cloud.cfg.d/99-datasource.cfg <<'EOF'
datasource_list: [NoCloud, None]
EOF

	# FIX_DHCP_REBOOT_BEGIN
	# Fix: Disable cloud-init network management so NetworkManager handles
	# DHCP persistently on every boot. Without this, cloud-init only configures
	# network on first boot (bringup=True) and skips on 2nd+ boots (bringup=False).
	cat >/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg <<'EOF'
network: {config: disabled}
EOF
	# FIX_DHCP_REBOOT_END

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
datasource: NoCloud
EOF

	echo "Enabling cloud-init services..."

	systemctl --root=/ enable cloud-init-local.service || true
	systemctl --root=/ enable cloud-init.service || true
	systemctl --root=/ enable cloud-config.service || true
	systemctl --root=/ enable cloud-final.service || true

	echo "Cleaning cloud-init state..."

	cloud-init clean --logs || true
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
		$(# shellcheck source=/dev/null
		. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
		tee /etc/apt/sources.list.d/docker.list > /dev/null
	apt update
	apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

	# Docker daemon config with custom data-root (aligned with template)
	mkdir -p /opt/docker-data /etc/docker
	cat > /etc/docker/daemon.json <<'EOF'
{"data-root": "/opt/docker-data"}
EOF

	# Disable Docker by default; cloud-init activates per host_type
	systemctl --root=/ disable docker || true

	# Remove Docker APT source so the target device won't try to reach download.docker.com
	rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg

	echo "Docker installed (disabled by default; cloud-init enables per host_type)."
}	

instal_k3s() {
	echo "Installing k3s..."
	
	# k3s version and integrity verification
	# Git commit of the installer script
	local COMMIT_HASH="5aed4d7beddeb3e67120da477c876ac9efd70318"
	local SCRIPT_URL="https://raw.githubusercontent.com/k3s-io/k3s/${COMMIT_HASH}/install.sh"
	# Matching SHA-256 hash for that exact commit
	local EXPECTED_HASH="46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad"
	
	local script_path="/tmp/k3s-install.sh"
	local actual_hash

	# Try to download from specified commit hash first, then fallback to latest
	for i in 1 2 3; do
		if curl -sfL --max-time 120 --retry 3 "$SCRIPT_URL" -o "$script_path"; then
			echo "  Successfully downloaded k3s installer from commit."
			break
		else
			echo "  k3s download attempt $i from commit failed, retrying..."
			if [ $i -eq 3 ]; then
				echo "  Falling back to latest k3s installer..."
				if curl -sfL --max-time 120 --retry 3 https://get.k3s.io -o "$script_path"; then
					echo "  Successfully downloaded latest k3s installer."
					echo "  WARNING: Using latest version - hash verification will be skipped"
					EXPECTED_HASH=""
					break
				else
					echo "ERROR: Failed to download k3s installer from both sources" >&2
					return 1
				fi
			fi
		fi
		sleep 10
	done

	# Verify script downloaded successfully
	if [ ! -f "$script_path" ]; then
		echo "ERROR: k3s install script not found at $script_path" >&2
		return 1
	fi

	# Verify hash if expected hash is set
	if [ -n "$EXPECTED_HASH" ]; then
		actual_hash=$(sha256sum "$script_path" | awk '{print $1}')
		if [ "$actual_hash" != "$EXPECTED_HASH" ]; then
			echo "CRITICAL: Script integrity failure!" >&2
			echo "  Expected hash: $EXPECTED_HASH" >&2
			echo "  Actual hash:   $actual_hash" >&2
			return 1
		fi
		echo "  Hash verification passed."
	else
		echo "  WARNING: Skipping hash verification (no expected hash set)"
	fi

	chmod +x "$script_path"

	INSTALL_K3S_EXEC="server --disable=traefik" \
		INSTALL_K3S_SKIP_ENABLE=true \
		INSTALL_K3S_SKIP_START=true \
		sh "$script_path"

	# K3s disabled by default; cloud-init activates per host_type
	systemctl --root=/ disable k3s || true
	
	echo "k3s installed (disabled by default; cloud-init enables per host_type)."
}

install_helm() {
	local commit_hash="3900f434fd3ef2b84065dc04508df48f288dba00"
	local script_url="https://raw.githubusercontent.com/helm/helm/${commit_hash}/scripts/get-helm-3"
	local expected_hash="38b65f882d9cae3891755bdb03becc6a01ae6f9cb24826c191f219ddfee70a5d"
	local actual_hash
	local script_path="/tmp/get_helm.sh"

	echo "Installing Helm..."
	if ! download_file "${script_url}" "${script_path}"; then
		echo "ERROR: Failed to download Helm installer"
		rm -f "${script_path}"
		return 1
	fi

	actual_hash=$(sha256sum "${script_path}" | awk '{print $1}')
	if [ "${actual_hash}" != "${expected_hash}" ]; then
		echo "ERROR: Helm installer checksum verification failed." >&2
		echo "Expected: ${expected_hash}" >&2
		echo "Actual:   ${actual_hash}" >&2
		rm -f "${script_path}"
		return 1
	fi

	chmod 700 "${script_path}"

	"${script_path}"

	rm -f "${script_path}"
	echo "Helm installed successfully."
}

install_realsense_pkgs(){
	echo "Installing Intel RealSense packages..."
	# ref: generic-handheld-os-server-template.yml packageRepositories section
	mkdir -p /etc/apt/keyrings
	local tmp_key_file="/tmp/librealsense.gpg"
	local librealsense_key_id="FB0B24895113F120"
	download_file "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${librealsense_key_id}" "${tmp_key_file}"
	verify_gpg_key_id "${tmp_key_file}" "${librealsense_key_id}"
	if ! gpg --dearmor -o /etc/apt/keyrings/librealsense.gpg "${tmp_key_file}" 2>/dev/null; then
		cp "${tmp_key_file}" /etc/apt/keyrings/librealsense.gpg
	fi
	rm -f "${tmp_key_file}"
	chmod 644 /etc/apt/keyrings/librealsense.gpg
	echo "deb [signed-by=/etc/apt/keyrings/librealsense.gpg] https://librealsense.intel.com/Debian/apt-repo $(lsb_release -cs) main" \
		| tee /etc/apt/sources.list.d/librealsense.list
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y \
		librealsense2 librealsense2-utils librealsense2-dev \
		librealsense2-dkms librealsense2-gl

	echo "Intel RealSense packages installed successfully."
}

install_eci_camera_hal_deps() {
	echo "Installing Intel ECI Camera HAL dependency packages..."
	apt-get update
	# Install all libia-*-ipu75xa packages (runtime + dev) from ECI repo
	DEBIAN_FRONTEND=noninteractive apt-get install -y \
		libia-aic-ipu75xa-dev \
		libia-aiq-v1-file-debug-ipu75xa-dev \
		libia-aiq-v1-file-debug-ipu75xa0 \
		libia-aiq-v1-ipu75xa-dev \
		libia-aiqb-parser-ipu75xa-dev \
		libia-bcomp-ipu75xa-dev \
		libia-cca-ipu75xa-dev \
		libia-ccat-ipu75xa-dev \
		libia-cmc-parser-ipu75xa-dev \
		libia-coordinate-ipu75xa-dev \
		libia-dvs-ipu75xa-dev \
		libia-emd-decoder-ipu75xa-dev \
		libia-exc-ipu75xa-dev \
		libia-lard-ipu75xa-dev \
		libia-log-ipu75xa-dev \
		libia-mkn-ipu75xa-dev \
		libia-nvm-ipu75xa-dev \
		libia-view-ipu75xa-dev \
		libia-view-ipu75xa0 \
		libipu75xa-dev 2>/dev/null || \
		echo "WARNING: Some libia/ipu75xa packages may not be available yet"
	# Also install any remaining libia-*-ipu75xa0 runtime packages via wildcard
	mapfile -t ipu75xa_runtime_packages < <(apt-cache search 'libia-.*-ipu75xa0' 2>/dev/null | awk '{print $1}')
	if [[ ${#ipu75xa_runtime_packages[@]} -gt 0 ]]; then
		DEBIAN_FRONTEND=noninteractive apt-get install -y "${ipu75xa_runtime_packages[@]}" 2>/dev/null || true
	fi
	# Install intel-mipi-gmsl-dkms (DKMS source only; module builds on first boot via dkms autoinstall)
	DEBIAN_FRONTEND=noninteractive apt-get install -y intel-mipi-gmsl-dkms 2>/dev/null || \
		echo "WARNING: intel-mipi-gmsl-dkms not available or failed to install"

	echo "ECI Camera HAL dependencies installed."
}


install_performance_tools() {
	echo "Installing performance analysis tools..."
	apt update
	apt install -y \
		linux-intel-bpftool \
		linux-intel-cpupower \
		linux-intel-misc-tools \
		linux-intel-perf \
		linux-intel-rtla \
		linux-intel-usbip \
		linux-intel-hyperv-daemons \
		libcpupower-intel-dev \
		linux-config-6.18 \
		linux-kbuild-6.18.38

	echo "Performance analysis tools installed successfully."
}

# LINUX_TOOLS_BIN_ALIAS_BLOCK_BEGIN
# REMOVE_WHEN_OVERLAY_SHIPS_CANONICAL_BIN_NAMES:
# The Intel overlay ships kernel user-space tools under linux-intel-* package names and
# frequently installs the executables with decorated names (e.g. usbip-intel,
# bpftool_6.18.38) or only under /usr/lib/linux-tools/<kver>/. Canonical's linux-tools-*
# packages expose them as plain commands on PATH (usbip, bpftool, perf, cpupower, rtla,
# turbostat, ...). This function reconciles the two by copying every executable shipped
# by those packages into /usr/local/bin under its undecorated Canonical name.
# Delete this function and its call in main() once the overlay names match upstream.
normalize_linux_tools_binary_names() {
	echo "Normalizing Intel linux-tools binary names to Canonical names..."

	local pkgs=(
		linux-intel-bpftool
		linux-intel-cpupower
		linux-intel-misc-tools
		linux-intel-perf
		linux-intel-rtla
		linux-intel-usbip
		linux-intel-sdsi
		linux-intel-hyperv-daemons
	)

	install -d -m 0755 /usr/local/bin

	local pkg file base canonical target
	for pkg in "${pkgs[@]}"; do
		if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
			echo "  skip ${pkg}: not installed"
			continue
		fi

		while IFS= read -r file; do
			# Only real executables; dpkg -L also lists directories, docs and man pages.
			if [ ! -f "$file" ] || [ ! -x "$file" ]; then
				continue
			fi
			case "$file" in
				/usr/share/*|/usr/src/*|/etc/*|/lib/systemd/*|/usr/lib/systemd/*) continue ;;
			esac

			base="$(basename "$file")"
			canonical="$base"
			# Strip overlay decorations: version suffixes and -intel/_intel markers.
			canonical="${canonical%%_6.[0-9]*}"
			canonical="${canonical%%-6.[0-9]*}"
			canonical="${canonical%-intel}"
			canonical="${canonical%_intel}"
			[ -n "$canonical" ] || continue

			# Already reachable on PATH under the canonical name from a standard bin dir.
			if [ "$canonical" = "$base" ]; then
				case "$file" in
					/usr/bin/*|/usr/sbin/*|/bin/*|/sbin/*)
						echo "  ok ${canonical}: already at ${file}"
						continue
						;;
				esac
			fi

			target="/usr/local/bin/${canonical}"
			if [ -e "$target" ] && [ ! -L "$target" ]; then
				echo "  keep ${target}: real file, not overwriting"
				continue
			fi

			cp -f "$file" "$target"
			chmod 0755 "$target"
			echo "  copy ${canonical} <- ${file}"
		done < <(dpkg -L "$pkg")
	done

	# rtla multiplexes its sub-tools through argv[0]; provide the upstream copies.
	if [ -e /usr/local/bin/rtla ] || command -v rtla >/dev/null 2>&1; then
		local rtla_bin
		rtla_bin="$(command -v rtla || echo /usr/local/bin/rtla)"
		local alias_name
		for alias_name in osnoise timerlat hwnoise; do
			if [ ! -e "/usr/local/bin/${alias_name}" ]; then
				cp -f "$rtla_bin" "/usr/local/bin/${alias_name}"
				chmod 0755 "/usr/local/bin/${alias_name}"
				echo "  copy ${alias_name} <- ${rtla_bin}"
			fi
		done
	fi

	hash -r 2>/dev/null || true
	echo "linux-tools binary names normalized."
}
# LINUX_TOOLS_BIN_ALIAS_BLOCK_END

install_gpu_npu_pkgs_from_deb() {
	echo "Installing NPU,GPU Packages.."

	# Create installation directory
	INSTALL_DIR="/tmp/install_gpu_cpu"
	mkdir -p "$INSTALL_DIR"
	cd "$INSTALL_DIR"

	# Downloading GPU drivers (aligned with overlay repo versions)
	# Intel-graphics-compiler Version: v2.38.2 (from GitHub releases, public)
	# GPU compute-runtime Version: 26.27.39122.11
	# Level-zero Version: v1.32.0 (packages renamed: level-zero→libze1, level-zero-devel→libze-dev)

	declare -A package_checksums=(
		["intel-igc-core-2_2.38.2+22051_amd64.deb"]="3dbcbe4e716d62e9bd43a4a476d724cf772b4581dbcdd096d70df382e7ccad7e"
		["intel-igc-opencl-2_2.38.2+22051_amd64.deb"]="e265d191590efd5491bfbbd148c144fdd40aea51e0b57f8651130d2da20b8186"
		["intel-ocloc_26.27.39122.11-0_amd64.deb"]="794a77217b3fd4c3f1381c2bb2c3c11a7f81e338b55b8a11e6c3b5070d138f98"
		["intel-opencl-icd_26.27.39122.11-0_amd64.deb"]="6e447a783c99fb5634df298c135a81165be07db98672df96cdf413d22f3e6ac4"
		["libze-intel-gpu1_26.27.39122.11-0_amd64.deb"]="58420df60d4bf8ac79aba03f7de1b8b60a93e995b18142391077ff735ce7b74b"
		["libze1_1.32.0+u24.04_amd64.deb"]="3c846af24f84a89150f6a4c6adcb4ea4ebef74dc119fe44f4e269bfaa72c7ba6"
		["libze-dev_1.32.0+u24.04_amd64.deb"]="4b783ed5fb937a55a7a0f3a8bc66af252f362e82476ebc0304da36173c9f2eb8"
		["linux-npu-driver-v1.35.0.20260722-29947505341-ubuntu2404.tar.gz"]="398343e53fdac6023ad0856ef88bb6011b1e12447a112be55e85e27ef7f96c66"
	)

	debpackage=(
		"https://github.com/intel/intel-graphics-compiler/releases/download/v2.38.2/intel-igc-core-2_2.38.2+22051_amd64.deb"
		"https://github.com/intel/intel-graphics-compiler/releases/download/v2.38.2/intel-igc-opencl-2_2.38.2+22051_amd64.deb"
		"https://github.com/intel/compute-runtime/releases/download/26.27.39122.11/intel-ocloc_26.27.39122.11-0_amd64.deb"
		"https://github.com/intel/compute-runtime/releases/download/26.27.39122.11/intel-opencl-icd_26.27.39122.11-0_amd64.deb"
		"https://github.com/intel/compute-runtime/releases/download/26.27.39122.11/libze-intel-gpu1_26.27.39122.11-0_amd64.deb"
		"https://github.com/oneapi-src/level-zero/releases/download/v1.32.0/libze1_1.32.0%2Bu24.04_amd64.deb"
		"https://github.com/oneapi-src/level-zero/releases/download/v1.32.0/libze-dev_1.32.0%2Bu24.04_amd64.deb")

	# Function to verify file integrity with SHA-256
	verify_checksum() {
		local file="$1"
		local expected_hash="$2"
		local actual_hash

		if [ "$expected_hash" = "REPLACE_WITH_ACTUAL_SHA256" ]; then
			echo "  WARNING: No checksum defined for $file - skipping verification"
			echo "  SECURITY RISK: Package integrity not verified!"
			return 0
		fi

		actual_hash=$(sha256sum "$file" | awk '{print $1}')
		if [ "$actual_hash" != "$expected_hash" ]; then
			echo "CRITICAL: Package integrity failure for $file!" >&2
			echo "  Expected hash: $expected_hash" >&2
			echo "  Actual hash:   $actual_hash" >&2
			return 1
		fi
		echo "  Checksum verification passed for $file"
		return 0
	}

	# Download and verify GPU packages
	echo "Downloading and verifying GPU packages..."
	for url in "${debpackage[@]}"; do
		echo "Downloading: $url"
		filename=$(basename "$url")
		if wget "$url" -O "$filename"; then
			echo "Successfully downloaded: $filename"
			
			# Verify checksum
			if [ -n "${package_checksums[$filename]}" ]; then
				if ! verify_checksum "$filename" "${package_checksums[$filename]}"; then
					echo "ERROR: Checksum verification failed for $filename"
					rm -f "$filename"
					exit 1
				fi
			else
				echo "  WARNING: No checksum found for $filename in verification table"
			fi
		else
			echo "ERROR: Failed to download $filename"
			exit 1
		fi
	done

	# Downloading NPU drivers
	# Version: v1.35.0.20260722 (from GitHub releases, public)
	# Aligned with ICT template: npu-linux-driver-ci-1.35.0.20260722-29947505341
	echo "Downloading NPU driver package..."
	npu_url="https://github.com/intel/linux-npu-driver/releases/download/v1.35.0/linux-npu-driver-v1.35.0.20260722-29947505341-ubuntu2404.tar.gz"
	npu_file="linux-npu-driver-v1.35.0.20260722-29947505341-ubuntu2404.tar.gz"

	if wget "$npu_url" -O "$npu_file"; then
		echo "Successfully downloaded NPU driver package"
		
		# Verify NPU package checksum
		if ! verify_checksum "$npu_file" "${package_checksums[$npu_file]}"; then
			echo "ERROR: NPU package checksum verification failed"
			rm -f "$npu_file"
			exit 1
		fi
		
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

	# Cleanup
	cd /
	rm -rf "$INSTALL_DIR"
	echo "Installation directory cleaned: $INSTALL_DIR"
}



install_intel_lpmd () {
	# Install dependencies to build intel-lpmd
	apt install -y autoconf autoconf-archive gcc libglib2.0-dev libdbus-1-dev libxml2-dev libnl-3-dev \
	         libnl-genl-3-dev libsystemd-dev gtk-doc-tools libupower-glib-dev automake
	cd /tmp
	git clone --branch v0.1.0 https://github.com/intel/intel-lpmd.git lpmd
	cd lpmd
	./autogen.sh
	make
	sudo make install
	# Remove restrictive hardware conditions so the service attempts to start
	# on all platforms. The daemon itself will exit gracefully if unsupported.
	mkdir -p /etc/systemd/system/intel_lpmd.service.d
	cat > /etc/systemd/system/intel_lpmd.service.d/override.conf <<EOF
[Unit]
# Clear all Condition* directives from the upstream unit
ConditionPathExists=
ConditionVirtualization=
EOF
	# NOTE: Not purging build dependencies — they are shared with dkms,
	# build-essential, intel-mipi-gmsl-dkms, and librealsense2-dkms.
	apt clean
	# Enable service
	systemctl --root=/ enable intel_lpmd.service
	echo "Installed intel-lpmd"
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

configure_system_services() {
	echo "Configuring system services (aligned with template configurations)..."

	# Mask systemd-networkd-wait-online — NetworkManager-wait-online already provides network-online.target
	systemctl --root=/ mask systemd-networkd-wait-online.service || true

	# Purge systemd-boot — installed transitively. GRUB is the actual bootloader.
	printf 'Package: systemd-boot systemd-boot-efi\nPin: release *\nPin-Priority: -1\n' > /etc/apt/preferences.d/no-systemd-boot
	dpkg --purge --force-all systemd-boot systemd-boot-efi 2>/dev/null || true

	# mDNS: enable Avahi and prevent systemd-resolved from conflicting
	mkdir -p /etc/systemd/system/multi-user.target.wants
	mkdir -p /etc/systemd/system/sockets.target.wants
	ln -sf /lib/systemd/system/avahi-daemon.service /etc/systemd/system/multi-user.target.wants/avahi-daemon.service || true
	ln -sf /lib/systemd/system/avahi-daemon.socket /etc/systemd/system/sockets.target.wants/avahi-daemon.socket || true
	mkdir -p /etc/systemd/resolved.conf.d
	printf '[Resolve]\nMulticastDNS=no\n' > /etc/systemd/resolved.conf.d/no-mdns.conf

	# Enable SSH service at boot (direct symlink for plain chroot)
	ln -sf /lib/systemd/system/ssh.service /etc/systemd/system/multi-user.target.wants/ssh.service || true

	# Remove ICT-generated ubuntu-noble.list — duplicates the Ubuntu 24.04 native ubuntu.sources (DEB822 format)
	rm -f /etc/apt/sources.list.d/ubuntu-noble.list

	# FIX_DHCP_REBOOT_BEGIN
	# Fix: Netplan with explicit DHCP config for all ethernet interfaces.
	# The original only declared renderer=NetworkManager with no interface
	# definitions, relying on cloud-init's 50-cloud-init.yaml which is
	# only generated on first boot.
	mkdir -p /etc/netplan
	cat > /etc/netplan/01-network-manager-all.yaml <<'EOF'
# Let NetworkManager manage all devices
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    all-en:
      match:
        name: "en*"
      dhcp4: true
      dhcp6: true
EOF
	chmod 600 /etc/netplan/01-network-manager-all.yaml

	# Remove cloud-init generated netplan to avoid conflicts
	rm -f /etc/netplan/50-cloud-init.yaml

	# Fix: Ensure NetworkManager actively manages all interfaces.
	# Docker-based Ubuntu images may have managed=false, causing
	# interfaces to show as "unmanaged" on 2nd boot.
	mkdir -p /etc/NetworkManager/conf.d
	cat > /etc/NetworkManager/conf.d/10-manage-all.conf <<'EOF'
[device]
wifi.scan-rand-mac-address=no

[ifupdown]
managed=true

[main]
plugins=keyfile

[keyfile]
unmanaged-devices=none
EOF
	# FIX_DHCP_REBOOT_END

	echo "System services configured."
}

main() {

	install_depended_packages

	create_ppa_sources_list

	download_and_install_gpg_key

	create_eci_sources_list

	download_and_install_eci_gpg_key

	create_openvino_oneapi_sources

	create_mozilla_ppa_sources

	set_preferred_package_list

	install_essential_tools

	audio_fw_update

	install_cloud_init

	install_docker

	instal_k3s

	install_helm

	# Kernel must be installed before DKMS packages (librealsense2-dkms,
	# intel-mipi-gmsl-dkms) so that headers are available for module builds.
	install_kernel

	install_realsense_pkgs

	install_eci_camera_hal_deps

	install_gpu_npu_pkgs_from_deb

	install_intel_lpmd

	install_performance_tools

	# LINUX_TOOLS_BIN_ALIAS_BLOCK_BEGIN
	normalize_linux_tools_binary_names
	# LINUX_TOOLS_BIN_ALIAS_BLOCK_END

	configure_system_services
}

main "$@"
echo "Edge node infrastructure setup completed successfully"
