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

# ---------------------------------------------------------------------------
# Repository / GPG key configuration
# ---------------------------------------------------------------------------
# Defaults point at the public Intel overlay on download.01.org 

INTEL_OVERLAY_URL="https://download.01.org/edge-linux-overlay/ubuntu"
INTEL_OVERLAY_COMPONENTS="main non-free multimedia kernels"
INTEL_OVERLAY_KEY_URL="https://download.01.org/edge-linux-overlay/ubuntu/9C63745D2A211728B8CE98C5F84B1B6A704E41B2.gpg"
INTEL_OVERLAY_KEY_FINGERPRINT="9C63745D2A211728B8CE98C5F84B1B6A704E41B2"

SOF_OPENMODULES_SHA256="0bc5c1942918e86f84b9a7e97efb7e82b9aad2891398927780d5afd433128f3f"
SOF_FIRMWARE_SHA256="ace80f314159034a2372c229a2a45443499649f6e747a63c7f2644464d399eba"
SOF_RT722_TOPOLOGY_SHA256="fedb1f01b91b14335cca4bc5d89992f224687e633455ca7c6f0b5c00fc9cac2d"
SOF_HDA_TOPOLOGY_SHA256="d2a6128569c980c39ecc48ab81ce253a9a3160f46e9ba843d7b056293388ee24"

MOZILLA_PPA_URL="https://ppa.launchpadcontent.net/mozillateam/ppa/ubuntu"
MOZILLA_PPA_KEY_URL="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x0AB215679C571D1C8325275B9BDB3D89CE49EC21"

INTEL_ECI_URL="https://eci.intel.com/repos/noble"
INTEL_ECI_KEY_URL="https://eci.intel.com/repos/gpg-keys/GPG-PUB-KEY-INTEL-ECI.gpg"
INTEL_ECI_KEY_FINGERPRINT="B1CDAB5E8EE9205CBD8A7500EF16D1B6C97E2FC9"
MOZILLA_PPA_KEY_FINGERPRINT="0AB215679C571D1C8325275B9BDB3D89CE49EC21"

# Modern per-repo scoped trust store (deprecates /etc/apt/trusted.gpg.d/).
APT_KEYRINGS_DIR="/etc/apt/keyrings"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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

install_depended_packages() {
	echo "Updating apt and installing initial packages..."
	apt update
	apt upgrade -y

	apt install -y --no-install-recommends wget curl ca-certificates gnupg ethtool libbpf1 wayland-protocols
	echo "Initial packages installed."
}

create_ppa_sources_list() {
    local SNAPSHOT_NAME="2026_S_REL3-meta-data-fix"
    echo "Creating Intel overlay repository sources list from snapshot ${SNAPSHOT_NAME}..."
    mkdir -p /etc/apt/sources.list.d
    cat > /etc/apt/sources.list.d/intel-ptl.list << EOF
deb [signed-by=${APT_KEYRINGS_DIR}/ptl.gpg] ${INTEL_OVERLAY_URL} noble/snapshots/${SNAPSHOT_NAME} ${INTEL_OVERLAY_COMPONENTS}
EOF

    echo "Intel overlay repository sources list created from frozen snapshot."
}

download_and_install_gpg_key() {
	echo "Downloading and installing GPG key..."
	install -d -m 0755 "${APT_KEYRINGS_DIR}"

	local tmp_key_file="/tmp/ptl.gpg"
	download_file "${INTEL_OVERLAY_KEY_URL}" "${tmp_key_file}"

	# Fingerprint pin. Skipped only when INTEL_OVERLAY_KEY_FINGERPRINT is
	# explicitly set to "" (e.g. when overriding INTEL_OVERLAY_KEY_URL to a
	# trusted internal mirror where TLS is the trust anchor). Left unset,
	# the public-key pin above is enforced.
	if [ -n "${INTEL_OVERLAY_KEY_FINGERPRINT}" ]; then
		local actual_fingerprint
		actual_fingerprint=$(gpg --show-keys --with-colons "${tmp_key_file}" | awk -F: '/^fpr:/ {print $10; exit}')
		if [ "${actual_fingerprint}" != "${INTEL_OVERLAY_KEY_FINGERPRINT}" ]; then
			echo "ERROR: Intel overlay GPG key fingerprint mismatch! Aborting."
			echo "Expected: ${INTEL_OVERLAY_KEY_FINGERPRINT}"
			echo "Actual:   ${actual_fingerprint}"
			rm -f "${tmp_key_file}"
			exit 1
		fi
		echo "Intel overlay GPG key fingerprint verified."
	else
		echo "Intel overlay GPG key fingerprint pin skipped (INTEL_OVERLAY_KEY_FINGERPRINT is empty)."
	fi

	# Dearmor into per-repo keyring. Fall back to a straight copy if the
	# source is already binary (dearmor exits non-zero in that case).
	if ! gpg --dearmor -o "${APT_KEYRINGS_DIR}/ptl.gpg" "${tmp_key_file}" 2>/dev/null; then
		cp "${tmp_key_file}" "${APT_KEYRINGS_DIR}/ptl.gpg"
	fi
	chmod 0644 "${APT_KEYRINGS_DIR}/ptl.gpg"
	rm -f "${tmp_key_file}"

	# Migration cleanup: remove the legacy globally-trusted key installed by
	# earlier revisions of this script.
	rm -f /etc/apt/trusted.gpg.d/ptl.gpg

	echo "Intel overlay GPG key installed at ${APT_KEYRINGS_DIR}/ptl.gpg."
}

# ---------------------------------------------------------------------------
# Configure APT preferences for Intel ECI repository
# ---------------------------------------------------------------------------
# Pins camera packages to ECI while blocking systemd packages to force them
# from canonical Ubuntu repos. Extracted as a separate function to keep
# install_camera_packages() readable.
configure_eci_apt_preferences() {
	local eci_host
	eci_host=$(printf '%s\n' "${INTEL_ECI_URL}" | awk -F/ '{print $3}')
	
	echo "Configuring APT preferences for ECI repository..."
	
	# Pin camera packages to ECI with priority 600 (higher than default 500)
	cat > /etc/apt/preferences.d/intel-eci << EOF
Package: libcamhal-ipu75xa0 libcamhal-ipu75xa libcamera-tools libcamhal-common libcamhal0 libia-*-ipu75xa0 gstreamer1.0-icamera libgsticamerainterface-1.0-1 intel-mipi-gmsl-dkms
Pin: origin ${eci_host}
Pin-Priority: 600
EOF
	
	# Block systemd and related packages from ECI (priority -1 = never install from this source)
	# Force these critical system packages to come from canonical Ubuntu repos only
	local -a blocked_packages=(
		"libnss-myhostname" "libnss-mymachines" "libnss-resolve"
		"libpam-systemd" "libsystemd-dev" "libsystemd0"
		"libudev-dev" "libudev1"
		"systemd-boot-efi" "systemd-boot" "systemd-container" "systemd-coredump"
		"systemd-dev" "systemd-homed" "systemd-journal-remote" "systemd-oomd"
		"systemd-resolved" "systemd-standalone-sysusers" "systemd-standalone-tmpfiles"
		"systemd-sysv" "systemd-tests" "systemd-timesyncd" "systemd-ukify"
		"systemd-userdbd" "systemd" "udev"
	)
	
	cat > /etc/apt/preferences.d/isar << 'EOFSTART'
# Default priority for all ECI packages (set to 500, same as Ubuntu default)
Package: *
Pin: origin eci.intel.com
Pin-Priority: 500

EOFSTART
	
	# Append blocked package rules
	for pkg in "${blocked_packages[@]}"; do
		cat >> /etc/apt/preferences.d/isar << EOF
Package: ${pkg}
Pin: origin eci.intel.com
Pin-Priority: -1

EOF
	done
	
	echo "APT preferences configured: camera packages pinned to ECI, systemd packages blocked."
}

install_camera_packages() {
	echo "Setting up Intel ECI repository and installing camera packages..."
	install -d -m 0755 "${APT_KEYRINGS_DIR}"
	
	# Download and install Intel ECI GPG key
	local tmp_key_file="/tmp/intel-eci.gpg"
	download_file "${INTEL_ECI_KEY_URL}" "${tmp_key_file}"
	verify_gpg_fingerprint "${tmp_key_file}" "${INTEL_ECI_KEY_FINGERPRINT}"
	
	# Dearmor into per-repo keyring
	if ! gpg --dearmor -o "${APT_KEYRINGS_DIR}/intel-eci.gpg" "${tmp_key_file}" 2>/dev/null; then
		cp "${tmp_key_file}" "${APT_KEYRINGS_DIR}/intel-eci.gpg"
	fi
	chmod 0644 "${APT_KEYRINGS_DIR}/intel-eci.gpg"
	rm -f "${tmp_key_file}"
	echo "Intel ECI GPG key installed at ${APT_KEYRINGS_DIR}/intel-eci.gpg."
	
	# Create Intel ECI repository sources list with proper GPG verification
	mkdir -p /etc/apt/sources.list.d
	cat > /etc/apt/sources.list.d/intel-eci.list << EOF
deb [signed-by=${APT_KEYRINGS_DIR}/intel-eci.gpg] ${INTEL_ECI_URL} isar main
EOF
	echo "Intel ECI repository configured."
	
	# Configure APT preferences for ECI packages
	configure_eci_apt_preferences
	
	# Install camera packages
	apt update
	export DEBIAN_FRONTEND=noninteractive
	
	# Pre-configure debconf to avoid interactive prompts (especially for DKMS packages)
	echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
	
	apt install -y \
		libcamhal-ipu75xa0 \
		libcamhal-ipu75xa \
		libcamera-tools \
		libcamhal-common \
		libcamhal0 \
		libia-*-ipu75xa0 \
		gstreamer1.0-icamera \
		libgsticamerainterface-1.0-1 \
		intel-mipi-gmsl-dkms 
	
	
	echo "Intel camera packages installed successfully."
}


set_preferred_package_list() {
	echo "Setting preferred package list..."
	# Derive the pin hostname from the repo URL so overriding INTEL_OVERLAY_URL
	# automatically updates the pin — no second value to keep in sync when
	# switching to an internal mirror.
	local overlay_host
	overlay_host=$(printf '%s\n' "${INTEL_OVERLAY_URL}" | awk -F/ '{print $3}')
	cat > /etc/apt/preferences.d/intel-ptl << EOF
Package: *
Pin: origin ${overlay_host}
Pin-Priority: 2000
EOF
}

install_essential_tools() {
	echo "Installing essential tools and dependencies..."
	apt update
	export DEBIAN_FRONTEND=noninteractive
	# --allow-downgrades: the Intel overlay is pinned at Priority 2000 so it
	# wins over the Ubuntu archive unconditionally, including for packages
	# where the overlay ships an OLDER version than noble-updates (e.g.
	# xserver-common, xserver-xorg-core). Without this flag apt aborts with
	# "Packages were downgraded and -y was used without --allow-downgrades".
	# Proper fix (deferred): narrow the pin to only the packages the overlay
	# is meant to own instead of Package: *.
	# Added dkms, v4l-utils, usb-modeswitch, clinfo, powertop.
	# Linux tools added in install_linux_tools() function. 
	apt install -y --allow-downgrades \
		systemd systemd-resolved udev initramfs-tools bsdutils gzip util-linux util-linux-extra \
		linux-base grub2-common grub-pc-bin grub-efi-amd64 grub-efi-amd64-bin grub-efi-amd64-signed efibootmgr shim-signed \
		ubuntu-minimal ubuntu-standard ubuntu-desktop-minimal \
		language-pack-en language-pack-en-base language-pack-gnome-en language-pack-gnome-en-base \
		linux-firmware firmware-sof-signed wireless-regdb \
		openssl libssl-dev \
		build-essential cmake make git git-lfs apt-transport-https gnupg lsb-release rsync dkms v4l-utils \
		python3-pip python3-netifaces libpython3.12t64 \
		libattr1 libconfig9 libnuma1 libslang2 libdw1t64 \
		libdrm2 libdrm-common libdrm-dev libdrm-intel1 libdrm-radeon1 libdrm-amdgpu1 libdrm-nouveau2 \
		mesa-vulkan-drivers mesa-utils intel-media-va-driver-non-free libigfxcmrt7 libigdgmm12 ocl-icd-libopencl1 \
		libva2 libva-drm2 libva-dev libva-glx2 libva-wayland2 libva-x11-2 libvpl2 libmfx-gen1.2 vainfo \
		ffmpeg libavcodec62 libavformat62 libavutil60 libavdevice62 libavfilter11 libswresample6 libswscale9 \
		libwayland-bin libwayland-client0 libwayland-cursor0 libwayland-dev libwayland-doc libwayland-egl-backend-dev \
		libwayland-egl1 libwayland-server0 weston libweston-10-0 \
		xserver-xorg-core libglew-dev libglm-dev \
		gir1.2-gst-plugins-bad-1.0 gir1.2-gstreamer-1.0 gstreamer1.0-plugins-bad gstreamer1.0-plugins-good \
		gstreamer1.0-plugins-base gstreamer1.0-pulseaudio libgstreamer1.0-0 libgstreamer-gl1.0-0 \
		libgstreamer-plugins-base1.0-0 libgstreamer-plugins-bad1.0-0 va-driver-all \
		libxdp1 libxdp-dev xdp-tools \
		libnl-3-200 libnl-genl-3-200 iproute2 net-tools iputils-ping tcpdump curl linuxptp dnsmasq-base network-manager \
		bluez \
		libtpms0 libtpms-dev \
		intel-gpu-tools thermald rpc-go lms metee stress-ng \
		pahole libbabeltrace1 libdebuginfod1t64 libopencsd1 libtracefs1 libtraceevent1 libpci3 pciutils \
		vim nano mc less file mawk grep diffutils findutils debianutils ncurses-base ncurses-bin cron msr-tools i2c-tools \
		lsscsi sg3-utils dosfstools gdisk pigz rpm \
		openssh-server chrony mosquitto mosquitto-clients socat dbus-x11 docker-compose efivar efibootmgr \
		libllvm18 libdebuginfod1t64 usb-modeswitch clinfo powertop
	
	systemctl --root=/ disable systemd-timesyncd || true
	systemctl --root=/ mask    systemd-timesyncd || true
	systemctl --root=/ enable ssh || true
	systemctl --root=/ enable  chrony || true  
	
	# Install libsdl2-dev separately with --no-install-recommends.
	# The bulk install with --allow-downgrades can silently skip this package
	# due to dependency conflicts. Installing separately with --no-install-recommends
	echo "Installing libsdl2-dev..."
	apt install -y --no-install-recommends libsdl2-dev
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

enable_display_manager() {
	echo "Enabling display manager for desktop environment..."
	apt install -y gdm3 || apt install -y lightdm
	systemctl --root=/ enable gdm3 2>/dev/null || systemctl --root=/ enable lightdm
	echo "Display manager enabled."
}

setup_firefox() {
	echo "Setting up Firefox (Mozilla Team PPA, scoped keyring)..."
	install -d -m 0755 "${APT_KEYRINGS_DIR}"

	# Fetch Mozilla Team PPA signing key and dearmor into a per-repo keyring.
	# Avoids 'add-apt-repository', which pulls keys via apt-key/keyserver into
	# the deprecated global trust store and does not set signed-by= on the list.
	local tmp_key_file="/tmp/mozillateam-ppa.gpg"
	download_file "${MOZILLA_PPA_KEY_URL}" "${tmp_key_file}"
	verify_gpg_fingerprint "${tmp_key_file}" "${MOZILLA_PPA_KEY_FINGERPRINT}"
	gpg --dearmor -o "${APT_KEYRINGS_DIR}/mozillateam-ppa.gpg" "${tmp_key_file}"
	rm -f "${tmp_key_file}"
	chmod 0644 "${APT_KEYRINGS_DIR}/mozillateam-ppa.gpg"

	cat > /etc/apt/sources.list.d/mozillateam-ppa.list << EOF
deb [signed-by=${APT_KEYRINGS_DIR}/mozillateam-ppa.gpg] ${MOZILLA_PPA_URL} noble main
EOF

	# Pin above the Ubuntu archive so we get the .deb Firefox rather than the
	# snap-transitional package Ubuntu ships by default.
	cat > /etc/apt/preferences.d/mozilla-firefox << EOF
Package: *
Pin: origin ppa.launchpadcontent.net
Pin-Priority: 1001
EOF

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

	# Download and verify both supported Panther Lake audio topologies.
	mkdir -p "$tplg_dir"
	download_and_verify_sha256 \
		"https://raw.githubusercontent.com/thesofproject/sof-bin/main/v2.13.x/sof-ipc4-tplg-v2.13/sof-ptl-rt722.tplg" \
		"$tplg_dir/sof-ptl-rt722.tplg" "${SOF_RT722_TOPOLOGY_SHA256}"
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

install_k3s() {
	# k3s version "v1.36.3+k3s1"
	COMMIT_HASH="5aed4d7beddeb3e67120da477c876ac9efd70318"
	SCRIPT_URL="https://raw.githubusercontent.com/k3s-io/k3s/${COMMIT_HASH}/install.sh"
	# Matching SHA-256 hash for that exact commit
	EXPECTED_HASH="46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad"
	echo "Installing k3s..."
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
	if [ -n "$EXPECTED_HASH" ] && [ "$EXPECTED_HASH" != "0" ]; then
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
		bash "$script_path"

	systemctl --root=/ enable k3s || true
	echo "k3s installed successfully."
}

install_helm() {
	# Install latest helm version v4.2.4
	COMMIT_HASH="3900f434fd3ef2b84065dc04508df48f288dba00"
	SCRIPT_URL="https://raw.githubusercontent.com/helm/helm/${COMMIT_HASH}/scripts/get-helm-3"
	# Matching SHA-256 hash for that exact commit
	EXPECTED_HASH="38b65f882d9cae3891755bdb03becc6a01ae6f9cb24826c191f219ddfee70a5d"
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
	bash ./get_helm.sh
	rm -f get_helm.sh
	echo "Helm installed successfully."
}

install_realsense_pkgs(){
	echo "Installing Intel RealSense packages..."
	# ref: https://docs.ros.org/en/iron/p/librealsense2/user_docs/distribution_linux.html
	mkdir -p /etc/apt/keyrings
	KEY_ID=$(curl -sSf "https://librealsense.intel.com/Debian/apt-repo/dists/$(lsb_release -cs)/InRelease" \
		| gpg --status-fd 1 --verify 2>/dev/null | grep "NO_PUBKEY" | awk '{print $3}')
	if [ -z "${KEY_ID}" ]; then
		echo "ERROR: Unable to determine the Intel RealSense GPG key ID." >&2
		return 1
	fi
	local tmp_key_file="/tmp/librealsense.gpg"
	download_file "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${KEY_ID}" "${tmp_key_file}"
	verify_gpg_key_id "${tmp_key_file}" "${KEY_ID}"
	if ! gpg --dearmor -o /etc/apt/keyrings/librealsense.gpg "${tmp_key_file}" 2>/dev/null; then
		cp "${tmp_key_file}" /etc/apt/keyrings/librealsense.gpg
	fi
	rm -f "${tmp_key_file}"
	chmod 644 /etc/apt/keyrings/librealsense.gpg
	echo "deb [signed-by=/etc/apt/keyrings/librealsense.gpg] https://librealsense.intel.com/Debian/apt-repo $(lsb_release -cs) main" \
		| tee /etc/apt/sources.list.d/librealsense.list
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y \
		librealsense2-dkms librealsense2 librealsense2-utils librealsense2-dev librealsense2-gl

	echo "Intel RealSense packages installed successfully."
}
install_gpu_npu_pkgs() {
	echo "Installing NPU,GPU Packages.."

	# Create installation directory
	INSTALL_DIR="/tmp/install_gpu_cpu"
	mkdir -p "$INSTALL_DIR"
	cd "$INSTALL_DIR"

	# Downloading GPU drivers (aligned with template configurations)
	# Intel-graphics-compiler Version: v2.38.2 (from GitHub releases, public)
	# GPU Version: 26.27.39122.11
	# Level-zero Version: v1.32.0 (packages renamed: level-zero->libze1, level-zero-devel->libze-dev)
	# Package URLs and their expected SHA-256 checksums
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
		"https://github.com/oneapi-src/level-zero/releases/download/v1.32.0/libze-dev_1.32.0%2Bu24.04_amd64.deb"
	)

	# Function to verify file integrity
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
	echo "Downloading NPU driver package..."
	# NPU version: v1.35.0.20260722-29947505341
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


install_linux_tools() {
	echo "Installing Linux tools..."
	apt update
	apt install -y \
		linux-kbuild-6.18.38 \
		linux-config-6.18 \
		linux-bpf-dev \
		linux-intel-bpftool \
		linux-intel-misc-tools \
		linux-intel-perf \
		linux-intel-cpupower \
		linux-intel-rtla \
		linux-intel-usbip \
		libcpupower-intel-dev \
		libcpupower-intel1 \
		linux-intel-hyperv-daemons \
		linux-intel-sdsi \
		linux-doc-6.18 \
		linux-doc-intel \
		linux-source-6.18 \
		linux-source-intel
	
	# --- Canonical names for the internal kernel tools ---------------------------
	# The linux-intel-* packages install their binaries with an `-intel` suffix
	# (bpftool-intel, perf-intel, ...). Move and rename them to canonical names
	# in /usr/local/{bin,sbin}, which PATH searches before /usr/bin and /usr/sbin.
	# misc-tools, hyperv-daemons and sdsi already install canonical names;
	# libcpupower-intel1/-dev use the standard soname. Nothing needed for those.
	# moved all tools as same as canonical names.
	
	echo "Moving kernel tools to canonical names..."
	mkdir -p /usr/local/bin /usr/local/sbin
	if [ -x /usr/sbin/bpftool-intel ]; then mv /usr/sbin/bpftool-intel /usr/local/sbin/bpftool || true; fi
	if [ -x /usr/bin/perf-intel ]; then mv /usr/bin/perf-intel /usr/local/bin/perf || true; fi
	if [ -x /usr/bin/cpupower-intel ]; then mv /usr/bin/cpupower-intel /usr/local/bin/cpupower || true; fi
	if [ -x /usr/bin/rtla-intel ]; then mv /usr/bin/rtla-intel /usr/local/bin/rtla || true; fi
	if [ -x /usr/sbin/usbip-intel ]; then mv /usr/sbin/usbip-intel /usr/local/sbin/usbip || true; fi
	if [ -x /usr/sbin/usbipd-intel ]; then mv /usr/sbin/usbipd-intel /usr/local/sbin/usbipd || true; fi
	# Copy bpftool and usbip to bin as well for non-root shells whose PATH omits sbin
	if [ -x /usr/local/sbin/bpftool ]; then cp /usr/local/sbin/bpftool /usr/local/bin/bpftool || true; fi
	if [ -x /usr/local/sbin/usbip ]; then cp /usr/local/sbin/usbip /usr/local/bin/usbip || true; fi
	# rtla sub-commands: create symlinks pointing to the rtla binary (rtla dispatches on argv[0])
	if [ -x /usr/local/bin/rtla ]; then for t in hwnoise osnoise timerlat; do ln -sf /usr/local/bin/rtla /usr/local/bin/"$t" || true; done; fi
	# Move other power tools to /usr/local/bin for consistency
	for t in turbostat intel-speed-select x86_energy_perf_policy; do if [ -x "/usr/sbin/$t" ]; then mv "/usr/sbin/$t" "/usr/local/bin/$t" || true; fi; done
	if [ -x /usr/sbin/intel_pstate_tracer.py ]; then mv /usr/sbin/intel_pstate_tracer.py /usr/local/bin/intel_pstate_tracer || true; fi
	# Update bash completions to canonical names
	if [ -f /usr/share/bash-completion/completions/bpftool-intel ]; then mv /usr/share/bash-completion/completions/bpftool-intel /usr/share/bash-completion/completions/bpftool || true; fi
	if [ -f /usr/share/bash-completion/completions/perf-intel ]; then mv /usr/share/bash-completion/completions/perf-intel /usr/share/bash-completion/completions/perf || true; fi
	# Rename man pages to canonical names
	for f in /usr/share/man/man1/{perf,rtla,bpftool,cpupower}-intel*.1.gz; do [ -e "$f" ] || continue; b=$(basename "$f"); n="${b/-intel/}"; if [ "$b" != "$n" ]; then mv "$f" "/usr/share/man/man1/$n" || true; fi; done
	# Rename cpupower systemd service to canonical name
	if [ -f /usr/lib/systemd/system/cpupower-intel.service ]; then mv /usr/lib/systemd/system/cpupower-intel.service /usr/lib/systemd/system/cpupower.service || true; fi
	# out-of-tree builds look for /lib/modules/$(uname -r)/build
	if [ -d /usr/lib/linux-kbuild-6.18.38 ]; then for k in /lib/modules/*-intel/build; do [ -e "$k" ] || ln -sf /usr/lib/linux-kbuild-6.18.38 "$k" || true; done; fi
	# Report what resolved, so a missing tool is visible in the build log.
	for t in bpftool perf cpupower rtla hwnoise osnoise timerlat usbip usbipd turbostat intel-speed-select x86_energy_perf_policy intel_pstate_tracer tmon thermometer bootconfig intel_sdsi hv_kvp_daemon; do p=$(command -v "$t" 2>/dev/null || true); echo "kernel-tool: $t -> ${p:-MISSING}"; done
	
	echo "Linux tools installed successfully."
}

main() {

	install_depended_packages

	create_ppa_sources_list

	download_and_install_gpg_key

	set_preferred_package_list

	install_essential_tools

	install_camera_packages

	build_install_lpmd

	enable_display_manager

	setup_firefox

	audio_fw_update

	install_cloud_init

	install_docker

	install_k3s

	install_helm

	install_realsense_pkgs

	install_gpu_npu_pkgs

	install_kernel

	install_linux_tools
}

main "$@"
echo "Edge node infrastructure setup completed successfully"
